"""add stats_charts table (custom charts on the Stats page)

Revision ID: d7f3a9c2b5e1
Revises: c4e8b2a61d07
Create Date: 2026-10-01 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import sqlmodel


# revision identifiers, used by Alembic.
revision: str = 'd7f3a9c2b5e1'
down_revision: Union[str, Sequence[str], None] = 'c4e8b2a61d07'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'stats_charts',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('title', sqlmodel.sql.sqltypes.AutoString(length=150), nullable=False),
        sa.Column('chart_type', sqlmodel.sql.sqltypes.AutoString(length=20), nullable=False),
        sa.Column('source', sqlmodel.sql.sqltypes.AutoString(length=30), nullable=False),
        sa.Column('group_by', sqlmodel.sql.sqltypes.AutoString(length=50), nullable=False),
        sa.Column('metric', sqlmodel.sql.sqltypes.AutoString(length=50), nullable=False),
        sa.Column('country', sqlmodel.sql.sqltypes.AutoString(length=20), nullable=True),
        sa.Column('months', sa.Integer(), nullable=True),
        sa.Column('created_at', sqlmodel.sql.sqltypes.UTCDateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_stats_charts_user_id'), 'stats_charts', ['user_id'], unique=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_stats_charts_user_id'), table_name='stats_charts')
    op.drop_table('stats_charts')
