"""client category, fair email, payment state, visa type detail, added-by

Replaces the free-text client_relation with created_by (who entered the
client) and moves visa_status to the new 15-step workflow.

Revision ID: 5e1c2a7d9f30
Revises: f3a7c9d21b4e
Create Date: 2026-09-30 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import sqlmodel


# revision identifiers, used by Alembic.
revision: str = '5e1c2a7d9f30'
down_revision: Union[str, Sequence[str], None] = 'f3a7c9d21b4e'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Old 4-state visa_status -> nearest step of the new workflow.
_VISA_STATUS_MAP = {
    'not_started': 'new',
    'pending': 'awaiting_result',
    'approved': 'passport_ready',
    'rejected': 'closed',
}
_VISA_TYPES = (
    'pre_entry_swift', 'government_invitation', 'first_entry_connect',
    'companion_s1_s2', 'study_x1_x2', 'visa_z', 'other',
)


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('clients', sa.Column('category', sqlmodel.sql.sqltypes.AutoString(length=20), nullable=False, server_default='normal'))
    op.add_column('clients', sa.Column('fair_email', sqlmodel.sql.sqltypes.AutoString(length=150), nullable=True))
    op.add_column('clients', sa.Column('visa_type_other', sqlmodel.sql.sqltypes.AutoString(length=150), nullable=True))
    op.add_column('clients', sa.Column('payment_state', sqlmodel.sql.sqltypes.AutoString(length=20), nullable=True))
    op.add_column('clients', sa.Column('created_by', sqlmodel.sql.sqltypes.AutoString(length=150), nullable=True))
    op.drop_column('clients', 'client_relation')

    for old, new in _VISA_STATUS_MAP.items():
        op.execute(sa.text("UPDATE clients SET visa_status = :new WHERE visa_status = :old").bindparams(old=old, new=new))
    # Free-text visa types become "other" with the old text kept as the detail.
    op.execute(
        sa.text(
            "UPDATE clients SET visa_type_other = visa_type, visa_type = 'other' "
            "WHERE visa_type IS NOT NULL AND visa_type NOT IN :types"
        ).bindparams(sa.bindparam('types', value=_VISA_TYPES, expanding=True))
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.add_column('clients', sa.Column('client_relation', sqlmodel.sql.sqltypes.AutoString(length=50), nullable=True))
    for old, new in _VISA_STATUS_MAP.items():
        op.execute(sa.text("UPDATE clients SET visa_status = :old WHERE visa_status = :new").bindparams(old=old, new=new))
    op.execute("UPDATE clients SET visa_type = visa_type_other WHERE visa_type = 'other'")
    op.drop_column('clients', 'created_by')
    op.drop_column('clients', 'payment_state')
    op.drop_column('clients', 'visa_type_other')
    op.drop_column('clients', 'fair_email')
    op.drop_column('clients', 'category')
