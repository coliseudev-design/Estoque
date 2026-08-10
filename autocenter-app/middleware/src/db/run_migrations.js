const db = require('./postgres');
async function run() {
  await db.checkConnection();
  await db.runMigrations();
  process.exit(0);
}
run();
