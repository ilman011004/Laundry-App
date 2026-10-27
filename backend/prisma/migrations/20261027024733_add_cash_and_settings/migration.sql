-- CreateEnum
CREATE TYPE "DepositStatus" AS ENUM ('PENDING', 'CONFIRMED');

-- CreateTable
CREATE TABLE "cash_deposits" (
    "id" SERIAL NOT NULL,
    "cashier_id" INTEGER NOT NULL,
    "amount" INTEGER NOT NULL,
    "note" TEXT,
    "status" "DepositStatus" NOT NULL DEFAULT 'PENDING',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "confirmed_at" TIMESTAMP(3),
    "confirmed_by_id" INTEGER,

    CONSTRAINT "cash_deposits_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "app_settings" (
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,

    CONSTRAINT "app_settings_pkey" PRIMARY KEY ("key")
);

-- CreateIndex
CREATE INDEX "cash_deposits_cashier_id_idx" ON "cash_deposits"("cashier_id");

-- CreateIndex
CREATE INDEX "cash_deposits_status_idx" ON "cash_deposits"("status");

-- AddForeignKey
ALTER TABLE "cash_deposits" ADD CONSTRAINT "cash_deposits_cashier_id_fkey" FOREIGN KEY ("cashier_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cash_deposits" ADD CONSTRAINT "cash_deposits_confirmed_by_id_fkey" FOREIGN KEY ("confirmed_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
