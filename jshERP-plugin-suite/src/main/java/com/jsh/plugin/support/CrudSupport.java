package com.jsh.plugin.support;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;

import java.sql.PreparedStatement;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 插件内单表增删改查的通用支撑：按 information_schema 校验字段，避免被前端传入任意列。
 */
public final class CrudSupport {

    private CrudSupport() {
    }

    private static final Map<String, List<String>> COLUMN_CACHE = new ConcurrentHashMap<String, List<String>>();

    /** 允许通过通用接口访问的插件表 */
    public static final List<String> TABLES = Arrays.asList(
            "jsh_vehicle", "jsh_customer_follow", "jsh_fa_category", "jsh_fa_asset", "jsh_fa_user_log",
            "jsh_commission_rule", "jsh_commission_ladder", "jsh_commission_record", "jsh_print_template",
            "jsh_af_flow", "jsh_af_flow_level", "jsh_lg_subject", "jsh_lg_account_set",
            "jsh_pd_bom", "jsh_pd_bom_item", "jsh_pd_bom_process", "jsh_pd_task",
            "jsh_pd_task_material", "jsh_pd_process_report", "jsh_pd_inspection", "jsh_pd_instock",
            "jsh_lg_voucher", "jsh_lg_voucher_entry", "jsh_sc_order", "jsh_sc_item",
            "jsh_af_instance", "jsh_af_task", "jsh_lg_period", "jsh_food_batch"
    );

    public static void checkTable(String table) {
        if (table == null || !TABLES.contains(table)) {
            throw new IllegalArgumentException("不支持的表：" + table);
        }
    }

    public static List<String> columns(JdbcTemplate jdbc, String table) {
        List<String> cached = COLUMN_CACHE.get(table);
        if (cached != null) {
            return cached;
        }
        List<String> list = new ArrayList<String>();
        List<Map<String, Object>> rows = jdbc.queryForList(
                "select column_name from information_schema.columns where table_schema = database() and table_name = ? order by ordinal_position",
                table);
        for (Map<String, Object> row : rows) {
            list.add(String.valueOf(row.get("column_name")).toLowerCase());
        }
        COLUMN_CACHE.put(table, list);
        return list;
    }

    public static boolean hasColumn(JdbcTemplate jdbc, String table, String column) {
        return columns(jdbc, table).contains(column.toLowerCase());
    }

    /** 取表中所有文本型字段，用于关键字模糊搜索 */
    public static List<String> textColumns(JdbcTemplate jdbc, String table) {
        List<String> list = new ArrayList<String>();
        List<Map<String, Object>> rows = jdbc.queryForList(
                "select column_name, data_type from information_schema.columns where table_schema = database() and table_name = ?",
                table);
        for (Map<String, Object> row : rows) {
            String type = String.valueOf(row.get("data_type")).toLowerCase();
            String name = String.valueOf(row.get("column_name")).toLowerCase();
            if ((type.contains("char") || type.contains("text")) && !name.equals("delete_flag")) {
                list.add(name);
            }
        }
        return list;
    }

    public static void insert(JdbcTemplate jdbc, String table, Map<String, Object> body, Long tenantId) {
        List<String> cols = columns(jdbc, table);
        StringBuilder names = new StringBuilder();
        StringBuilder marks = new StringBuilder();
        List<Object> values = new ArrayList<Object>();
        for (Map.Entry<String, Object> e : body.entrySet()) {
            String key = e.getKey().toLowerCase();
            if (!cols.contains(key) || "id".equals(key)) {
                continue;
            }
            Object value = e.getValue();
            if (value instanceof Collection || value instanceof Map) {
                continue;
            }
            if (names.length() > 0) {
                names.append(",");
                marks.append(",");
            }
            names.append(key);
            marks.append("?");
            values.add(value);
        }
        if (cols.contains("tenant_id") && !body.containsKey("tenant_id")) {
            if (names.length() > 0) {
                names.append(",");
                marks.append(",");
            }
            names.append("tenant_id");
            marks.append("?");
            values.add(tenantId);
        }
        if (cols.contains("delete_flag") && !body.containsKey("delete_flag")) {
            if (names.length() > 0) {
                names.append(",");
                marks.append(",");
            }
            names.append("delete_flag");
            marks.append("?");
            values.add("0");
        }
        String sql = "insert into " + table + " (" + names + ") values (" + marks + ")";
        final Object[] params = values.toArray();
        KeyHolder keyHolder = new GeneratedKeyHolder();
        jdbc.update(con -> {
            PreparedStatement ps = con.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS);
            for (int i = 0; i < params.length; i++) {
                ps.setObject(i + 1, params[i]);
            }
            return ps;
        }, keyHolder);
        Number key = keyHolder.getKey();
        body.put("id", key == null ? null : key.longValue());
    }

    public static void update(JdbcTemplate jdbc, String table, Long id, Map<String, Object> body) {
        List<String> cols = columns(jdbc, table);
        StringBuilder set = new StringBuilder();
        List<Object> values = new ArrayList<Object>();
        for (Map.Entry<String, Object> e : body.entrySet()) {
            String key = e.getKey().toLowerCase();
            if (!cols.contains(key) || "id".equals(key) || "table".equals(key)) {
                continue;
            }
            Object value = e.getValue();
            if (value instanceof Collection || value instanceof Map) {
                continue;
            }
            if (set.length() > 0) {
                set.append(",");
            }
            set.append(key).append("=?");
            values.add(value);
        }
        if (set.length() == 0) {
            return;
        }
        values.add(id);
        jdbc.update("update " + table + " set " + set + " where id = ?", values.toArray());
    }

    public static void softDelete(JdbcTemplate jdbc, String table, Long id) {
        if (hasColumn(jdbc, table, "delete_flag")) {
            jdbc.update("update " + table + " set delete_flag = '1' where id = ?", id);
        } else {
            jdbc.update("delete from " + table + " where id = ?", id);
        }
    }

    public static Long longVal(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return Long.parseLong(String.valueOf(value).trim());
        } catch (Exception e) {
            return null;
        }
    }
}
