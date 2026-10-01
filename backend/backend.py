from fastapi import Depends, FastAPI, Request, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

import base64
import json
import os
import re
import requests
import traceback
from datetime import date, datetime, timezone

from backend.db import get_session
from backend.models import (
    AgencyRequest,
    AgencyRequestCreate,
    BankAccount,
    BankTransaction,
    BankTransactionCreate,
    Client,
    ClientCreate,
    ClientFile,
    EmployeeRequest,
    EmployeeRequestCreate,
    Invoice,
    InvoiceCreate,
    Payslip,
    PayslipCreate,
    TreasuryEntry,
    TreasuryEntryCreate,
    User,
)
from backend.photos import UPLOADS_DIR, delete_photo, save_client_file, save_client_photo
from backend.invoices import generate_invoice_pdf
from backend.payroll import DEFAULT_COMPANY, compute_payslip, generate_payslip_pdf, legacy_details, parse_pointage
from backend.auth import (
    create_access_token,
    decode_access_token,
    get_current_user,
    hash_password,
    new_confirmation_token,
    require_admin,
    send_signup_request_email,
    user_out,
    verify_password,
)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Paths that don't require a logged-in session.
_PUBLIC_PATHS = {"/auth/signup", "/auth/login", "/docs", "/openapi.json", "/redoc"}
_PUBLIC_PREFIXES = ("/auth/confirm/", "/auth/reject/")
# Only an Admin may use these (mirrors what the sidebar shows an Admin vs an Agent).
_ADMIN_ONLY_PREFIXES = ("/treasury", "/banking", "/invoices", "/payroll", "/agency-requests")


@app.middleware("http")
async def require_auth(request: Request, call_next):
    path = request.url.path
    if path in _PUBLIC_PATHS or path.startswith(_PUBLIC_PREFIXES) or request.method == "OPTIONS":
        return await call_next(request)

    token = request.query_params.get("token")
    auth_header = request.headers.get("authorization", "")
    if not token and auth_header.lower().startswith("bearer "):
        token = auth_header[7:]

    if not token:
        return JSONResponse(status_code=401, content={"detail": "Not authenticated"})

    try:
        payload = decode_access_token(token)
    except HTTPException as e:
        return JSONResponse(status_code=e.status_code, content={"detail": e.detail})

    if path.startswith(_ADMIN_ONLY_PREFIXES) and payload.get("role") != "Admin":
        return JSONResponse(status_code=403, content={"detail": "Admin access required"})

    request.state.user_email = payload.get("email")
    return await call_next(request)

QWEN_API_URL = "http://localhost:11434/v1/chat/completions"
CHAT_MODEL = "qwen2.5vl:3b-8k"

FIELDS = [
    "country",
    "passport_number",
    "type",
    "nationality",
    "given_name",
    "surname",
    "date_of_birth",
    "sex",
    "place_of_birth",
    "date_of_issue",
    "date_of_expiry",
    "issued_by"
]

# Path the browser uses to reach this API (Vite proxies /api -> :8001 and strips the prefix)
PUBLIC_API_PREFIX = os.getenv("PUBLIC_API_PREFIX", "/api")


def passport_images(session: Session, client_ids: list[int] | None = None) -> dict[int, str]:
    """URL of each client's passport scan among their uploaded files — an
    image whose name mentions "passport", else their first uploaded image
    (the Add client page uploads the passport first). Used as the picture
    for clients that have no photo of their own."""
    query = select(ClientFile).where(ClientFile.content_type.like("image/%")).order_by(ClientFile.id)
    if client_ids is not None:
        query = query.where(ClientFile.client_id.in_(client_ids))
    chosen: dict[int, ClientFile] = {}
    for f in session.exec(query).all():
        current = chosen.get(f.client_id)
        if current is None or ("passport" in f.filename.lower() and "passport" not in current.filename.lower()):
            chosen[f.client_id] = f
    return {cid: f"{PUBLIC_API_PREFIX}/clients/{cid}/files/{f.id}" for cid, f in chosen.items()}


def client_out(client: Client, passport_image: str = "") -> dict:
    data = client.model_dump(exclude={"photo_path"})
    data["user_photo"] = (
        f"{PUBLIC_API_PREFIX}/clients/{client.id}/photo" if client.photo_path else ""
    )
    data["passport_image"] = passport_image
    return data


@app.get("/clients")
def get_clients(session: Session = Depends(get_session)):
    clients = session.exec(select(Client).order_by(Client.id)).all()
    passports = passport_images(session)
    return [client_out(c, passports.get(c.id, "")) for c in clients]


@app.get("/clients/{client_id}/photo")
def get_client_photo(client_id: int, session: Session = Depends(get_session)):
    client = session.get(Client, client_id)
    if not client or not client.photo_path:
        raise HTTPException(status_code=404, detail="Photo not found")
    path = UPLOADS_DIR / client.photo_path
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Photo not found")
    return FileResponse(path, media_type="image/jpeg")


@app.post("/clients", status_code=201)
def add_client(
    data: ClientCreate, user: User = Depends(get_current_user), session: Session = Depends(get_session)
):
    client = Client.model_validate(data.model_dump(exclude={"user_photo"}))
    client.created_by = user.name
    session.add(client)
    photo_path = None
    try:
        session.flush()  # assigns client.id
        if data.user_photo:
            photo_path = save_client_photo(client.id, data.user_photo)
            client.photo_path = photo_path
        session.commit()
    except IntegrityError:
        session.rollback()
        delete_photo(photo_path)
        raise HTTPException(
            status_code=409,
            detail=f"A client with passport number {data.passport_number} already exists",
        )
    except ValueError as e:
        session.rollback()
        raise HTTPException(status_code=422, detail=str(e))
    session.refresh(client)
    return {"status": "success", "client": client_out(client)}


@app.put("/clients/{client_id}")
def update_client(client_id: int, data: ClientCreate, session: Session = Depends(get_session)):
    client = session.get(Client, client_id)
    if not client:
        raise HTTPException(status_code=404, detail="Client not found")

    for key, value in data.model_dump(exclude={"user_photo"}).items():
        setattr(client, key, value)

    old_photo_path = client.photo_path
    new_photo_path = None
    try:
        if data.user_photo:
            new_photo_path = save_client_photo(client.id, data.user_photo)
            client.photo_path = new_photo_path
        session.add(client)
        session.commit()
    except IntegrityError:
        session.rollback()
        delete_photo(new_photo_path)
        raise HTTPException(
            status_code=409,
            detail=f"A client with passport number {data.passport_number} already exists",
        )
    except ValueError as e:
        session.rollback()
        raise HTTPException(status_code=422, detail=str(e))
    session.refresh(client)
    if new_photo_path and old_photo_path and old_photo_path != new_photo_path:
        delete_photo(old_photo_path)
    return {"status": "success", "client": client_out(client, passport_images(session, [client.id]).get(client.id, ""))}


@app.delete("/clients/{client_id}")
def delete_client(client_id: int, session: Session = Depends(get_session)):
    client = session.get(Client, client_id)
    if not client:
        raise HTTPException(status_code=404, detail="Client not found")

    files = session.exec(select(ClientFile).where(ClientFile.client_id == client_id)).all()
    for f in files:
        session.delete(f)
    session.commit()  # remove client_files first — no ORM relationship() links these tables

    photo_path = client.photo_path
    session.delete(client)
    session.commit()

    delete_photo(photo_path)
    for f in files:
        delete_photo(f.path)
    return {"status": "success"}


def client_file_out(f: ClientFile) -> dict:
    return {
        "id": f.id,
        "filename": f.filename,
        "content_type": f.content_type,
        "uploaded_at": f.uploaded_at.isoformat(),
        "url": f"{PUBLIC_API_PREFIX}/clients/{f.client_id}/files/{f.id}",
    }


@app.get("/clients/{client_id}/files")
def list_client_files(client_id: int, session: Session = Depends(get_session)):
    files = session.exec(
        select(ClientFile).where(ClientFile.client_id == client_id).order_by(ClientFile.id)
    ).all()
    return [client_file_out(f) for f in files]


@app.post("/clients/{client_id}/files", status_code=201)
async def upload_client_files(
    client_id: int,
    files: list[UploadFile] = File(...),
    session: Session = Depends(get_session),
):
    client = session.get(Client, client_id)
    if not client:
        raise HTTPException(status_code=404, detail="Client not found")

    saved = []
    for file in files:
        raw = await file.read()
        rel_path = save_client_file(client_id, file.filename or "file", raw)
        record = ClientFile(
            client_id=client_id,
            filename=file.filename or "file",
            path=rel_path,
            content_type=file.content_type,
        )
        session.add(record)
        session.flush()
        saved.append(record)

    session.commit()
    for record in saved:
        session.refresh(record)
    return [client_file_out(f) for f in saved]


@app.get("/clients/{client_id}/files/{file_id}")
def get_client_file(client_id: int, file_id: int, session: Session = Depends(get_session)):
    record = session.get(ClientFile, file_id)
    if not record or record.client_id != client_id:
        raise HTTPException(status_code=404, detail="File not found")
    path = UPLOADS_DIR / record.path
    if not path.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(path, media_type=record.content_type or "application/octet-stream", filename=record.filename)


@app.delete("/clients/{client_id}/files/{file_id}")
def delete_client_file(client_id: int, file_id: int, session: Session = Depends(get_session)):
    record = session.get(ClientFile, file_id)
    if not record or record.client_id != client_id:
        raise HTTPException(status_code=404, detail="File not found")
    session.delete(record)
    session.commit()
    delete_photo(record.path)
    return {"status": "success"}


@app.post("/auth/signup")
def signup(data: dict, session: Session = Depends(get_session)):
    name = (data.get("name") or "").strip()
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""

    if not name or not email or "@" not in email:
        raise HTTPException(status_code=422, detail="A valid name and email are required")
    if len(password) < 8:
        raise HTTPException(status_code=422, detail="Password must be at least 8 characters")

    existing = session.exec(select(User).where(User.email == email)).first()
    if existing:
        raise HTTPException(status_code=409, detail="An account with this email already exists")

    token, expires = new_confirmation_token()
    user = User(
        name=name,
        email=email,
        password_hash=hash_password(password),
        role="Agent",
        status="pending",
        confirmation_token=token,
        confirmation_expires=expires,
    )
    session.add(user)
    session.commit()
    session.refresh(user)

    try:
        send_signup_request_email(user, token)
    except Exception:
        traceback.print_exc()

    return {"status": "pending", "message": "Request submitted. An admin must approve it before you can sign in."}


@app.post("/auth/login")
def login(data: dict, session: Session = Depends(get_session)):
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""

    user = session.exec(select(User).where(User.email == email)).first()
    if not user or not verify_password(password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    if user.status == "pending":
        raise HTTPException(status_code=403, detail="Your account is awaiting admin approval")
    if user.status != "active":
        raise HTTPException(status_code=403, detail="This account is not active")

    return {"token": create_access_token(user, remember=bool(data.get("remember"))), "user": user_out(user)}


@app.get("/auth/me")
def me(user: User = Depends(get_current_user)):
    return user_out(user)


@app.get("/auth/confirm/{token}")
def confirm_signup(token: str, session: Session = Depends(get_session)):
    user = session.exec(select(User).where(User.confirmation_token == token)).first()
    if not user or user.status != "pending":
        raise HTTPException(status_code=404, detail="This request no longer exists")
    if user.confirmation_expires and user.confirmation_expires < datetime.now(timezone.utc):
        raise HTTPException(status_code=410, detail="This confirmation link has expired")

    user.status = "active"
    user.confirmation_token = None
    user.confirmation_expires = None
    session.add(user)
    session.commit()
    return {"status": "success", "message": f"{user.email} approved"}


@app.get("/auth/reject/{token}")
def reject_signup(token: str, session: Session = Depends(get_session)):
    user = session.exec(select(User).where(User.confirmation_token == token)).first()
    if not user or user.status != "pending":
        raise HTTPException(status_code=404, detail="This request no longer exists")

    user.status = "rejected"
    user.confirmation_token = None
    user.confirmation_expires = None
    session.add(user)
    session.commit()
    return {"status": "success", "message": f"{user.email} rejected"}


@app.get("/auth/pending")
def list_pending_users(_: User = Depends(require_admin), session: Session = Depends(get_session)):
    users = session.exec(select(User).where(User.status == "pending").order_by(User.created_at)).all()
    return [user_out(u) for u in users]


@app.get("/auth/users")
def list_users(_: User = Depends(require_admin), session: Session = Depends(get_session)):
    users = session.exec(select(User).order_by(User.created_at)).all()
    return [user_out(u) for u in users]


@app.post("/auth/users/{user_id}/approve")
def approve_user(user_id: int, _: User = Depends(require_admin), session: Session = Depends(get_session)):
    user = session.get(User, user_id)
    if not user or user.status != "pending":
        raise HTTPException(status_code=404, detail="Pending request not found")
    user.status = "active"
    user.confirmation_token = None
    user.confirmation_expires = None
    session.add(user)
    session.commit()
    return user_out(user)


@app.post("/auth/users/{user_id}/reject")
def reject_user(user_id: int, _: User = Depends(require_admin), session: Session = Depends(get_session)):
    user = session.get(User, user_id)
    if not user or user.status != "pending":
        raise HTTPException(status_code=404, detail="Pending request not found")
    user.status = "rejected"
    user.confirmation_token = None
    user.confirmation_expires = None
    session.add(user)
    session.commit()
    return user_out(user)


@app.delete("/auth/users/{user_id}")
def delete_user(user_id: int, admin: User = Depends(require_admin), session: Session = Depends(get_session)):
    if user_id == admin.id:
        raise HTTPException(status_code=400, detail="You can't remove your own account")
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    session.delete(user)
    session.commit()
    return {"status": "success"}


@app.post("/auth/users/{user_id}/role")
def set_user_role(
    user_id: int, data: dict, admin: User = Depends(require_admin), session: Session = Depends(get_session)
):
    role = data.get("role")
    if role not in ("Admin", "Agent"):
        raise HTTPException(status_code=422, detail="role must be 'Admin' or 'Agent'")
    if user_id == admin.id:
        raise HTTPException(status_code=400, detail="You can't change your own role")
    user = session.get(User, user_id)
    if not user or user.status != "active":
        raise HTTPException(status_code=404, detail="Active user not found")
    user.role = role
    session.add(user)
    session.commit()
    return user_out(user)


@app.post("/chat")
async def chat(payload: dict):
    """
    payload: {
      "messages": [{"role": "user" | "assistant", "content": "..."}, ...],
      "image": "data:image/png;base64,..."   # optional, e.g. a live-helper screenshot
    }
    Attaches "image" (if present) to the last user message and forwards the
    conversation to the local Qwen vision model running in Ollama.
    """
    messages = payload.get("messages") or []
    image = payload.get("image")

    if not messages:
        raise HTTPException(status_code=400, detail="messages is required")

    oai_messages = []
    last_user_index = max(
        (i for i, m in enumerate(messages) if m.get("role") == "user"), default=-1
    )

    for i, m in enumerate(messages):
        role = m.get("role")
        content = m.get("content", "")
        if role not in ("user", "assistant", "system"):
            continue

        if i == last_user_index and image:
            oai_messages.append(
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": content},
                        {"type": "image_url", "image_url": {"url": image}},
                    ],
                }
            )
        else:
            oai_messages.append({"role": role, "content": content})

    request_payload = {
        "model": CHAT_MODEL,
        "messages": oai_messages,
        "temperature": 0.4,
        "max_tokens": 800,
    }

    try:
        response = requests.post(QWEN_API_URL, json=request_payload, timeout=120)
        response.raise_for_status()
        result = response.json()
        reply = result["choices"][0]["message"]["content"]
    except requests.exceptions.RequestException as e:
        raise HTTPException(
            status_code=502,
            detail=f"Could not reach the local model at {QWEN_API_URL}: {e}",
        )
    except (KeyError, IndexError):
        raise HTTPException(status_code=502, detail="Unexpected response from the model")

    return {"reply": reply}


@app.post("/extract")
async def extract_passport(file: UploadFile = File(...)):

    print("\n==============================")
    print("EXTRACTION REQUEST")
    print("==============================")

    try:

        print("Filename:", file.filename)
        print("Content type:", file.content_type)

        if not file.content_type or not file.content_type.startswith("image/"):
            raise HTTPException(
                status_code=400,
                detail="Please upload an image."
            )

        image_bytes = await file.read()

        print("Image size:", len(image_bytes), "bytes")

        image_base64 = base64.b64encode(image_bytes).decode("utf-8")

        prompt = f"""
Extract the information from this passport image. 

Also locate the passport owner's portrait photograph and return its bounding box as normalized integers on a 0 to 1000 scale in exact format [ymin, xmin, ymax, xmax].

IMPORTANT INSTRUCTIONS:
1. Return ONLY a single valid JSON object starting with {{ and ending with }}.
2. Provide all text values strictly in English (Latin characters only). Do NOT include secondary languages, Arabic, or slash translation values (e.g. use "Male" or "M" instead of "M / ذكر", use "Tunis" instead of "Tunis / تونس").
3. Do not include markdown code block formatting, backticks, or extra text.
4. Do not invent information.

Use exactly these keys:

{json.dumps(FIELDS + ["photo_bbox"], indent=2)}

`photo_bbox`: [ymin, xmin, ymax, xmax] normalized integers from 0 to 1000 for the portrait photo of the passport holder (top-left y, top-left x, bottom-right y, bottom-right x). Example: [150, 40, 650, 350]. If not found, use [].

If a text field cannot be read, use an empty string.

Dates must use YYYY-MM-DD format.
"""

        payload = {
            "model": "qwen2.5vl:3b-8k",

            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": prompt
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:{file.content_type};base64,{image_base64}"
                            }
                        }
                    ]
                }
            ],

            "temperature": 0,
            "max_tokens": 1000
        }

        print("\nSending request to:")
        print(QWEN_API_URL)

        response = requests.post(
            QWEN_API_URL,
            json=payload,
            timeout=120
        )

        print("\nQWEN STATUS:", response.status_code)
        print("\nQWEN RESPONSE:")
        print(response.text[:5000])

        response.raise_for_status()

        result = response.json()

        model_output = result["choices"][0]["message"]["content"]

        print("\nMODEL OUTPUT:")
        print(model_output)

        # Remove markdown code blocks if present
        cleaned_output = re.sub(r"```(?:json)?", "", model_output).strip()

        # Fix invalid model JSON output where model uses [ ... ] with key:value pairs instead of { ... }
        if cleaned_output.startswith("[") and cleaned_output.endswith("]"):
            cleaned_output = "{" + cleaned_output[1:-1] + "}"

        try:
            extracted = json.loads(cleaned_output)
        except json.JSONDecodeError:
            try:
                json_match = re.search(r"\{.*\}", cleaned_output, re.DOTALL)
                clean_json_str = json_match.group(0) if json_match else cleaned_output
                extracted = json.loads(clean_json_str)
            except json.JSONDecodeError:
                print("Failed to parse JSON from output:", cleaned_output)
                extracted = {}

        def clean_language(val):
            if not val or not isinstance(val, str):
                return ""
            val = val.strip()
            # If value contains slashes (e.g. "M / ذكر" or "Tunis / تونس"), keep the first English/Latin part
            if "/" in val:
                parts = [p.strip() for p in val.split("/")]
                for p in parts:
                    if re.search(r"[a-zA-Z0-9]", p):
                        return p
                return parts[0]
            return val

        def normalize_date(val):
            if not val or not isinstance(val, str):
                return ""
            val = val.strip()
            if re.match(r"^\d{4}-\d{2}-\d{2}$", val):
                return val
            m = re.match(r"^(\d{2})[/.-](\d{2})[/.-](\d{4})$", val)
            if m:
                return f"{m.group(3)}-{m.group(2)}-{m.group(1)}"
            m = re.match(r"^(\d{4})[/.-](\d{2})[/.-](\d{2})$", val)
            if m:
                return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
            return val

        date_fields = {"date_of_birth", "date_of_issue", "date_of_expiry"}
        final_data = {}

        for field in FIELDS:
            val = extracted.get(field, "")
            if val is None:
                val = ""
            val = str(val).strip()
            val = clean_language(val)
            if field in date_fields:
                val = normalize_date(val)
            final_data[field] = val

        # Crop owner photo using returned bounding box
        user_photo_b64 = ""
        bbox = extracted.get("photo_bbox")
        if bbox and isinstance(bbox, list) and len(bbox) == 4:
            try:
                from PIL import Image
                import io

                img = Image.open(io.BytesIO(image_bytes))
                width, height = img.size
                c1, c2, c3, c4 = bbox

                # Determine scale and format
                if max(c1, c2, c3, c4) <= 1.0:
                    ymin, xmin, ymax, xmax = int(c1 * height), int(c2 * width), int(c3 * height), int(c4 * width)
                elif max(c1, c2, c3, c4) <= 1000 and max(c3, c4) <= 1000 and (width > 1000 or height > 1000):
                    ymin = int(c1 * height / 1000.0)
                    xmin = int(c2 * width / 1000.0)
                    ymax = int(c3 * height / 1000.0)
                    xmax = int(c4 * width / 1000.0)
                else:
                    ymin, xmin, ymax, xmax = int(c1), int(c2), int(c3), int(c4)

                # Ensure min < max
                if ymin > ymax:
                    ymin, ymax = ymax, ymin
                if xmin > xmax:
                    xmin, xmax = xmax, xmin

                # Clamp values
                xmin, xmax = max(0, min(xmin, width)), max(0, min(xmax, width))
                ymin, ymax = max(0, min(ymin, height)), max(0, min(ymax, height))

                print(f"Calculated Crop Bounding Box: xmin={xmin}, ymin={ymin}, xmax={xmax}, ymax={ymax} (Image: {width}x{height})")

                if xmax > xmin and ymax > ymin:
                    cropped = img.crop((xmin, ymin, xmax, ymax))
                    buffered = io.BytesIO()
                    cropped.save(buffered, format="JPEG")
                    cropped_b64 = base64.b64encode(buffered.getvalue()).decode("utf-8")
                    user_photo_b64 = f"data:image/jpeg;base64,{cropped_b64}"
            except Exception as crop_err:
                print("Error cropping passport photo:", crop_err)

        final_data["user_photo"] = user_photo_b64

        print("\nFINAL DATA:")
        print(json.dumps(final_data, indent=2))

        return final_data

    except HTTPException:
        raise

    except Exception as e:

        print("\n!!!!!!!!!!!!!!!!!!!!!!!!")
        print("ERROR")
        print("!!!!!!!!!!!!!!!!!!!!!!!!")

        traceback.print_exc()

        raise HTTPException(
            status_code=500,
            detail=str(e)
        )

# =====================================================================
# ============================  TREASURY  ==============================
# =====================================================================

def treasury_entry_out(e: TreasuryEntry) -> dict:
    data = e.model_dump()
    data["entry_date"] = e.entry_date.isoformat()
    data["created_at"] = e.created_at.isoformat()
    return data


@app.get("/treasury")
def get_treasury(country: str, session: Session = Depends(get_session)):
    today = date.today()
    month_start = today.replace(day=1)

    entries = session.exec(
        select(TreasuryEntry)
        .where(TreasuryEntry.country == country, TreasuryEntry.entry_date >= month_start)
        .order_by(TreasuryEntry.entry_date.desc(), TreasuryEntry.id.desc())
    ).all()

    spending = sum(e.price for e in entries if e.kind == "spending")
    gathering = sum(e.price for e in entries if e.kind == "gathering")

    history_rows = session.exec(
        select(
            func.date_trunc("month", TreasuryEntry.entry_date).label("month"),
            TreasuryEntry.kind,
            func.sum(TreasuryEntry.price),
        )
        .where(TreasuryEntry.country == country)
        .group_by("month", TreasuryEntry.kind)
        .order_by("month")
    ).all()

    history_map = {}
    for month, kind, total in history_rows:
        key = month.strftime("%Y-%m")
        row = history_map.setdefault(key, {"month": key, "spending": 0, "gathering": 0})
        row[kind] = float(total)
    history = [history_map[k] for k in sorted(history_map)]
    for row in history:
        row["net"] = row["gathering"] - row["spending"]

    return {
        "current_month": {
            "month": month_start.strftime("%Y-%m"),
            "spending": spending,
            "gathering": gathering,
            "net": gathering - spending,
            "entries": [treasury_entry_out(e) for e in entries],
        },
        "history": history,
    }


@app.post("/treasury", status_code=201)
def add_treasury_entry(data: TreasuryEntryCreate, session: Session = Depends(get_session)):
    entry = TreasuryEntry.model_validate(data)
    session.add(entry)
    session.commit()
    session.refresh(entry)
    return treasury_entry_out(entry)


@app.delete("/treasury/{entry_id}")
def delete_treasury_entry(entry_id: int, session: Session = Depends(get_session)):
    entry = session.get(TreasuryEntry, entry_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Entry not found")
    session.delete(entry)
    session.commit()
    return {"status": "success"}


# =====================================================================
# ============================  BANKING  ===============================
# =====================================================================

@app.get("/banking/accounts")
def get_bank_accounts(country: str, session: Session = Depends(get_session)):
    accounts = session.exec(
        select(BankAccount).where(BankAccount.country == country).order_by(BankAccount.id)
    ).all()
    return accounts


@app.post("/banking/accounts", status_code=201)
def add_bank_account(data: BankAccount, session: Session = Depends(get_session)):
    account = BankAccount(**data.model_dump(exclude={"id"}))
    session.add(account)
    session.commit()
    session.refresh(account)
    return account


@app.get("/banking/accounts/{account_id}/transactions")
def get_bank_transactions(account_id: int, session: Session = Depends(get_session)):
    return session.exec(
        select(BankTransaction)
        .where(BankTransaction.account_id == account_id)
        .order_by(BankTransaction.entry_date.desc(), BankTransaction.id.desc())
    ).all()


@app.post("/banking/accounts/{account_id}/transactions", status_code=201)
def add_bank_transaction(
    account_id: int, data: BankTransactionCreate, session: Session = Depends(get_session)
):
    account = session.get(BankAccount, account_id)
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")

    tx = BankTransaction.model_validate({**data.model_dump(), "account_id": account_id})
    account.balance = account.balance + tx.amount
    session.add(tx)
    session.add(account)
    session.commit()
    session.refresh(tx)
    return tx


@app.delete("/banking/accounts/{account_id}/transactions/{tx_id}")
def delete_bank_transaction(account_id: int, tx_id: int, session: Session = Depends(get_session)):
    tx = session.get(BankTransaction, tx_id)
    if not tx or tx.account_id != account_id:
        raise HTTPException(status_code=404, detail="Transaction not found")
    account = session.get(BankAccount, account_id)
    if account:
        account.balance = account.balance - tx.amount
        session.add(account)
    session.delete(tx)
    session.commit()
    return {"status": "success"}


@app.delete("/banking/accounts/{account_id}")
def delete_bank_account(account_id: int, session: Session = Depends(get_session)):
    account = session.get(BankAccount, account_id)
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    for tx in session.exec(select(BankTransaction).where(BankTransaction.account_id == account_id)).all():
        session.delete(tx)
    session.delete(account)
    session.commit()
    return {"status": "success"}


# =====================================================================
# ============================  INVOICES  ==============================
# =====================================================================

def make_invoice_number(session: Session, country: str, doc_type: str) -> str:
    prefix = "FAC" if doc_type == "facture" else "REC"
    country_code = "TN" if country == "tunisia" else "LY" if country == "libya" else country.upper()[:2]
    year = date.today().year
    count = session.exec(
        select(func.count()).select_from(Invoice).where(
            Invoice.country == country, Invoice.doc_type == doc_type,
            func.extract("year", Invoice.issue_date) == year,
        )
    ).one()
    return f"{prefix}-{country_code}-{year}-{count + 1:04d}"


def invoice_out(inv: Invoice) -> dict:
    data = inv.model_dump()
    data["issue_date"] = inv.issue_date.isoformat()
    data["created_at"] = inv.created_at.isoformat()
    data["items"] = json.loads(inv.items_json or "[]")
    data["pdf_url"] = f"{PUBLIC_API_PREFIX}/invoices/{inv.id}/pdf"
    return data


@app.get("/invoices")
def list_invoices(country: str, session: Session = Depends(get_session)):
    invoices = session.exec(
        select(Invoice).where(Invoice.country == country).order_by(Invoice.id.desc())
    ).all()
    return [invoice_out(i) for i in invoices]


@app.post("/invoices", status_code=201)
def create_invoice(data: InvoiceCreate, session: Session = Depends(get_session)):
    number = make_invoice_number(session, data.country, data.doc_type)
    payload = data.model_dump(exclude={"items"})
    payload["items_json"] = json.dumps([i.model_dump() for i in data.items])
    invoice = Invoice(**payload, number=number)
    session.add(invoice)
    session.commit()
    session.refresh(invoice)
    return invoice_out(invoice)


@app.get("/invoices/{invoice_id}/pdf")
def get_invoice_pdf(invoice_id: int, session: Session = Depends(get_session)):
    invoice = session.get(Invoice, invoice_id)
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")
    try:
        pdf_path = generate_invoice_pdf(invoice)
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Could not generate PDF: {e}")
    return FileResponse(pdf_path, media_type="application/pdf", filename=f"{invoice.number}.pdf")


@app.delete("/invoices/{invoice_id}")
def delete_invoice(invoice_id: int, session: Session = Depends(get_session)):
    invoice = session.get(Invoice, invoice_id)
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")
    session.delete(invoice)
    session.commit()
    return {"status": "success"}


# =====================================================================
# ===========================  REQUESTS  ================================
# =====================================================================

@app.get("/agency-requests")
def list_agency_requests(session: Session = Depends(get_session)):
    return session.exec(select(AgencyRequest).order_by(AgencyRequest.id.desc())).all()


@app.post("/agency-requests", status_code=201)
def create_agency_request(data: AgencyRequestCreate, session: Session = Depends(get_session)):
    req = AgencyRequest.model_validate(data)
    session.add(req)
    session.commit()
    session.refresh(req)
    return req


@app.delete("/agency-requests/{request_id}")
def delete_agency_request(request_id: int, session: Session = Depends(get_session)):
    req = session.get(AgencyRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Request not found")
    session.delete(req)
    session.commit()
    return {"status": "success"}


@app.get("/employee-requests")
def list_employee_requests(user: User = Depends(get_current_user), session: Session = Depends(get_session)):
    # Private between each agent and the admin: an agent only ever sees their
    # own requests, while the admin sees everyone's.
    query = select(EmployeeRequest).order_by(EmployeeRequest.id.desc())
    if user.role != "Admin":
        query = query.where(EmployeeRequest.user_email == user.email)
    return session.exec(query).all()


@app.post("/employee-requests", status_code=201)
def create_employee_request(
    data: EmployeeRequestCreate, user: User = Depends(get_current_user), session: Session = Depends(get_session)
):
    req = EmployeeRequest.model_validate(data, update={"user_email": user.email})
    session.add(req)
    session.commit()
    session.refresh(req)
    return req


@app.delete("/employee-requests/{request_id}")
def delete_employee_request(request_id: int, _: User = Depends(require_admin), session: Session = Depends(get_session)):
    req = session.get(EmployeeRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Request not found")
    session.delete(req)
    session.commit()
    return {"status": "success"}


# =====================================================================
# ============================  PAYROLL  ================================
# =====================================================================

@app.post("/payroll/parse-pointage")
async def parse_pointage_file(file: UploadFile = File(...)):
    raw = await file.read()
    try:
        rows = parse_pointage(raw)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Could not read the Excel file: {e}")
    return rows


def payslip_out(p: Payslip) -> dict:
    data = p.model_dump(exclude={"details_json"})
    data["net_total"] = p.net_total if p.net_total is not None else p.gross_total
    data["details"] = json.loads(p.details_json) if p.details_json else legacy_details(p.hours, p.hourly_rate)
    return data


@app.get("/payroll/payslips")
def list_payslips(session: Session = Depends(get_session)):
    return [payslip_out(p) for p in session.exec(select(Payslip).order_by(Payslip.id.desc())).all()]


@app.post("/payroll/payslips", status_code=201)
def create_payslip(data: PayslipCreate, session: Session = Depends(get_session)):
    if data.hourly_rate <= 0:
        raise HTTPException(status_code=422, detail="Hourly rate must be greater than 0")
    if data.advances < 0 or data.pause < 0:
        raise HTTPException(status_code=422, detail="Advances and pause cannot be negative")

    if data.rows:
        result = compute_payslip(data.rows, {
            "rate": data.hourly_rate, "advances": data.advances, "pause": data.pause,
            "m25": data.m25, "m50": data.m50, "m100": data.m100,
        })
        result["company"] = {
            key: (getattr(data, key) or "").strip() or default for key, default in DEFAULT_COMPANY.items()
        }
        payslip = Payslip(
            employee_name=data.employee_name,
            matricule=data.matricule,
            period_label=f"{result['month']:02d}/{result['year']}",
            hours=round(result["worked_minutes"] / 60, 2),
            hourly_rate=data.hourly_rate,
            currency=data.currency,
            gross_total=result["gross"],
            advances=data.advances,
            net_total=result["net"],
            details_json=json.dumps(result, ensure_ascii=False),
        )
    else:
        # Older clients (the iOS app) only send hours × rate.
        if data.hours is None:
            raise HTTPException(status_code=422, detail="Either rows or hours is required")
        gross = round(data.hours * data.hourly_rate, 3)
        payslip = Payslip(
            employee_name=data.employee_name,
            period_label=data.period_label or date.today().strftime("%m/%Y"),
            hours=data.hours,
            hourly_rate=data.hourly_rate,
            currency=data.currency,
            gross_total=gross,
            net_total=gross,
        )

    session.add(payslip)
    session.commit()
    session.refresh(payslip)
    return payslip_out(payslip)


@app.get("/payroll/payslips/{payslip_id}/pdf")
def get_payslip_pdf(payslip_id: int, session: Session = Depends(get_session)):
    payslip = session.get(Payslip, payslip_id)
    if not payslip:
        raise HTTPException(status_code=404, detail="Payslip not found")
    try:
        pdf_path = generate_payslip_pdf(payslip)
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Could not generate PDF: {e}")
    return FileResponse(pdf_path, media_type="application/pdf", filename=f"payslip-{payslip.id}.pdf")


@app.delete("/payroll/payslips/{payslip_id}")
def delete_payslip(payslip_id: int, session: Session = Depends(get_session)):
    payslip = session.get(Payslip, payslip_id)
    if not payslip:
        raise HTTPException(status_code=404, detail="Payslip not found")
    session.delete(payslip)
    session.commit()
    return {"status": "success"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.backend:app", host="0.0.0.0", port=8001, reload=True)  # run from the project root

