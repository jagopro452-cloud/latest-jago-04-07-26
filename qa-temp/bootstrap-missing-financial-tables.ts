import { pool } from "../canonical-app/server/db";

async function main() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS booking_intents (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      customer_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
      status VARCHAR(40) NOT NULL DEFAULT 'initiated',
      quoted_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
      payment_method VARCHAR(40),
      trip_type VARCHAR(40) NOT NULL DEFAULT 'normal',
      payload JSONB NOT NULL DEFAULT '{}'::jsonb,
      razorpay_order_id VARCHAR(120),
      razorpay_payment_id VARCHAR(120),
      trip_id UUID,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_booking_intents_customer ON booking_intents(customer_id);
    CREATE INDEX IF NOT EXISTS idx_booking_intents_status ON booking_intents(status);
    CREATE UNIQUE INDEX IF NOT EXISTS idx_booking_intents_order
      ON booking_intents(razorpay_order_id)
      WHERE razorpay_order_id IS NOT NULL;
    CREATE UNIQUE INDEX IF NOT EXISTS idx_booking_intents_payment
      ON booking_intents(razorpay_payment_id)
      WHERE razorpay_payment_id IS NOT NULL;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS company_wallet_events (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      company_id UUID NOT NULL REFERENCES b2b_companies(id) ON DELETE CASCADE,
      amount NUMERIC(12,2) NOT NULL,
      type VARCHAR(16) NOT NULL,
      reason TEXT NOT NULL,
      ref_id TEXT,
      metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_company_wallet_events_company
      ON company_wallet_events(company_id, created_at DESC);
  `);

  console.log("bootstrapped booking_intents and company_wallet_events");
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
