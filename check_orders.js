const { pool } = require('./middleware/src/db/postgres');
async function run() {
    try {
        const { rows } = await pool.query('SELECT id, branch_id, sync_status FROM orders ORDER BY created_at DESC LIMIT 5');
        console.log(rows);
    } catch(e) {
        console.error(e);
    } finally {
        pool.end();
    }
}
run();
