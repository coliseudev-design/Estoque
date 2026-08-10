const { pool } = require('../db/postgres');

class ErpConfigService {
  async upsertPaymentSpecies(tenantId, speciesList) {
    if (!speciesList || speciesList.length === 0) return 0;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const values = [];
      const placeholders = speciesList.map((item, index) => {
        const offset = index * 5;
        values.push(
          tenantId,
          parseInt(item.id || item.erp_id, 10),
          item.descricao || item.description || '',
          item.tipo?.toString() || null,
          item.active !== false
        );
        return `($${offset + 1}, $${offset + 2}, $${offset + 3}, $${offset + 4}, $${offset + 5})`;
      }).join(', ');

      const query = `
        INSERT INTO payment_species (tenant_id, erp_id, description, tipo, active)
        VALUES ${placeholders}
        ON CONFLICT (tenant_id, erp_id) 
        DO UPDATE SET
            description = EXCLUDED.description,
            tipo = EXCLUDED.tipo,
            active = EXCLUDED.active,
            updated_at = NOW()
      `;

      const result = await client.query(query, values);
      await client.query('COMMIT');
      return result.rowCount;
    } catch (error) {
      await client.query('ROLLBACK');
      console.error('[ErpConfigService] Erro no upsert de especies de pagamento:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  async upsertPaymentConditions(tenantId, conditionsList) {
    if (!conditionsList || conditionsList.length === 0) return 0;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const values = [];
      const placeholders = conditionsList.map((item, index) => {
        const offset = index * 6;
        values.push(
          item.id, // ID composto: ID_FORMA_ID_ESPECIE
          tenantId,
          item.especieId ? parseInt(item.especieId, 10) : null,
          item.formaId ? parseInt(item.formaId, 10) : null,
          item.descricao || '',
          item.active !== false
        );
        return `($${offset + 1}, $${offset + 2}, $${offset + 3}, $${offset + 4}, $${offset + 5}, $${offset + 6})`;
      }).join(', ');

      const query = `
        INSERT INTO payment_conditions (id, tenant_id, especie_id, forma_id, descricao, active)
        VALUES ${placeholders}
        ON CONFLICT (id) 
        DO UPDATE SET
            especie_id = EXCLUDED.especie_id,
            forma_id = EXCLUDED.forma_id,
            descricao = EXCLUDED.descricao,
            active = EXCLUDED.active,
            updated_at = NOW()
      `;

      const result = await client.query(query, values);
      await client.query('COMMIT');
      return result.rowCount;
    } catch (error) {
      await client.query('ROLLBACK');
      console.error('[ErpConfigService] Erro no upsert de condicoes de pagamento:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  async upsertNaturezasOperacao(tenantId, naturezasList) {
    if (!naturezasList || naturezasList.length === 0) return 0;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const values = [];
      const placeholders = naturezasList.map((item, index) => {
        const offset = index * 10;
        values.push(
          tenantId,
          parseInt(item.id || item.erp_id, 10),
          item.descricao || '',
          item.descricaoNota || null,
          item.codigoFiscal?.toString() || null,
          item.es ? parseInt(item.es, 10) : null,
          item.processo ? parseInt(item.processo, 10) : null,
          item.tipo ? parseInt(item.tipo, 10) : null,
          item.mobOrdem ? parseInt(item.mobOrdem, 10) : null,
          item.active !== false
        );
        return `($${offset + 1}, $${offset + 2}, $${offset + 3}, $${offset + 4}, $${offset + 5}, $${offset + 6}, $${offset + 7}, $${offset + 8}, $${offset + 9}, $${offset + 10})`;
      }).join(', ');

      const query = `
        INSERT INTO naturezas_operacao (tenant_id, erp_id, descricao, descricao_nota, codigo_fiscal, es, processo, tipo, mob_ordem, active)
        VALUES ${placeholders}
        ON CONFLICT (tenant_id, erp_id) 
        DO UPDATE SET
            descricao = EXCLUDED.descricao,
            descricao_nota = EXCLUDED.descricao_nota,
            codigo_fiscal = EXCLUDED.codigo_fiscal,
            es = EXCLUDED.es,
            processo = EXCLUDED.processo,
            tipo = EXCLUDED.tipo,
            mob_ordem = EXCLUDED.mob_ordem,
            active = EXCLUDED.active,
            updated_at = NOW()
      `;

      const result = await client.query(query, values);
      await client.query('COMMIT');
      return result.rowCount;
    } catch (error) {
      await client.query('ROLLBACK');
      console.error('[ErpConfigService] Erro no upsert de naturezas de operacao:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  async getPaymentSpecies(tenantId) {
    const res = await pool.query(
      `SELECT erp_id AS id, description, tipo FROM payment_species WHERE tenant_id = $1 AND active = true ORDER BY description`,
      [tenantId]
    );
    return res.rows;
  }

  async getPaymentConditions(tenantId) {
    const res = await pool.query(
      `SELECT id, especie_id AS "especieId", forma_id AS "formaId", descricao FROM payment_conditions WHERE tenant_id = $1 AND active = true ORDER BY descricao`,
      [tenantId]
    );
    return res.rows;
  }

  async getNaturezasOperacao(tenantId) {
    const res = await pool.query(
      `SELECT erp_id AS id, descricao, descricao_nota AS "descricaoNota", codigo_fiscal AS "codigoFiscal", es, processo, tipo, mob_ordem AS "mobOrdem" FROM naturezas_operacao WHERE tenant_id = $1 AND active = true ORDER BY mob_ordem, descricao`,
      [tenantId]
    );
    return res.rows;
  }
}

module.exports = new ErpConfigService();
