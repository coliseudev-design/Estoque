const { pool } = require('../db/postgres');

class CatalogService {
  /**
   * Faz o upsert em lote do catálogo vindo do Worker (Firebird)
   * @param {string} tenantId Identificador do Tenant (VPS)
   * @param {Array} catalog Lote de objetos de catalogo
   */
  async upsertBatch(tenantId, catalog) {
    if (!catalog || catalog.length === 0) return 0;

    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      const values = [];
      const placeholders = catalog.map((item, index) => {
        const offset = index * 8;
        values.push(
          tenantId,
          item.erp_id,
          item.name,
          item.category || 'Geral',
          item.price || 0,
          item.brand || null,
          item.code || null,
          item.active !== false
        );
        return `($${offset + 1}, $${offset + 2}, $${offset + 3}, $${offset + 4}, $${offset + 5}, $${offset + 6}, $${offset + 7}, $${offset + 8})`;
      }).join(', ');

      const query = `
        INSERT INTO catalog (tenant_id, erp_id, name, category, price, brand, code, active)
        VALUES ${placeholders}
        ON CONFLICT (tenant_id, erp_id) 
        DO UPDATE SET
            name = EXCLUDED.name,
            category = EXCLUDED.category,
            price = EXCLUDED.price,
            brand = EXCLUDED.brand,
            code = EXCLUDED.code,
            active = EXCLUDED.active,
            updated_at = NOW()
      `;

      const result = await client.query(query, values);
      await client.query('COMMIT');
      
      return result.rowCount;
    } catch (error) {
      await client.query('ROLLBACK');
      console.error('[CatalogService] Erro no upsert em lote:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Retorna os itens ativos de catálogo de um Tenant para o Mobile PULL
   * Opcional: filtrar apenas a partir de uma data de atualização (sync delta)
   */
  async getActiveCatalog(tenantId, sinceStr = null) {
    const values = [tenantId];
    let query = `
      SELECT erp_id, name, category, price, brand, code, active 
      FROM catalog 
      WHERE tenant_id = $1 AND active = true
    `;

    if (sinceStr) {
      // Se houver uma data, pegamos apenas atualizados após ela
      const sinceDate = new Date(sinceStr);
      if (!isNaN(sinceDate.getTime())) {
        query += ` AND updated_at > $2`;
        values.push(sinceDate);
      }
    }

    query += ` ORDER BY category, name`;

    const result = await pool.query(query, values);
    return result.rows;
  }
}

module.exports = new CatalogService();
