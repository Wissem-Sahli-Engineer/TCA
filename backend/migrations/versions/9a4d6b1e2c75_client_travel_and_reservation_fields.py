"""client travel and reservation fields

Revision ID: 9a4d6b1e2c75
Revises: 5e1c2a7d9f30
Create Date: 2026-09-30 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import sqlmodel


# revision identifiers, used by Alembic.
revision: str = '9a4d6b1e2c75'
down_revision: Union[str, Sequence[str], None] = '5e1c2a7d9f30'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('clients', sa.Column('has_flight', sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column('clients', sa.Column('flight_date', sa.Date(), nullable=True))
    op.add_column('clients', sa.Column('destination', sqlmodel.sql.sqltypes.AutoString(length=150), nullable=True))
    op.add_column('clients', sa.Column('airline_name', sqlmodel.sql.sqltypes.AutoString(length=150), nullable=True))
    op.add_column('clients', sa.Column('hotel_reservation', sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column('clients', sa.Column('hotel_name', sqlmodel.sql.sqltypes.AutoString(length=150), nullable=True))
    op.add_column('clients', sa.Column('duration', sqlmodel.sql.sqltypes.AutoString(length=50), nullable=True))
    op.add_column('clients', sa.Column('reservation_amount', sa.Float(), nullable=True))
    # Currency is now a pick-list (USD, EUR, TND, LYD); normalise case.
    op.execute("UPDATE clients SET currency = UPPER(TRIM(currency)) WHERE currency IS NOT NULL")


def downgrade() -> None:
    """Downgrade schema."""
    for column in (
        'reservation_amount', 'duration', 'hotel_name', 'hotel_reservation',
        'airline_name', 'destination', 'flight_date', 'has_flight',
    ):
        op.drop_column('clients', column)
