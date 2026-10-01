"""payslip breakdown fields (matricule, advances, net, details_json)

Revision ID: c4e8b2a61d07
Revises: 9a4d6b1e2c75
Create Date: 2026-10-01 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import sqlmodel


revision: str = 'c4e8b2a61d07'
down_revision: Union[str, Sequence[str], None] = '9a4d6b1e2c75'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('payslips', sa.Column('matricule', sqlmodel.sql.sqltypes.AutoString(length=50), nullable=True))
    op.add_column('payslips', sa.Column('advances', sa.Float(), nullable=False, server_default='0'))
    op.add_column('payslips', sa.Column('net_total', sa.Float(), nullable=True))
    op.add_column('payslips', sa.Column('details_json', sqlmodel.sql.sqltypes.AutoString(), nullable=True))
    op.execute("UPDATE payslips SET net_total = gross_total WHERE net_total IS NULL")


def downgrade() -> None:
    op.drop_column('payslips', 'details_json')
    op.drop_column('payslips', 'net_total')
    op.drop_column('payslips', 'advances')
    op.drop_column('payslips', 'matricule')
