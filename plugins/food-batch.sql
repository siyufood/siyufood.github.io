-- 思雨食品 ERP · 批次与效期模块（可重复执行）
-- 执行顺序：jsh_erp.sql -> plugin-schema.sql -> plugin-menu.sql -> 本脚本
SET NAMES utf8mb4;

-- 1) 批次台账表：生产日期 + 保质期天数 -> 到期日；数量为批次当前在库数量
CREATE TABLE IF NOT EXISTS `jsh_food_batch` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `batch_no` varchar(64) DEFAULT NULL COMMENT '批次号',
  `material_id` bigint(20) DEFAULT NULL COMMENT '商品ID',
  `material_name` varchar(255) DEFAULT NULL COMMENT '商品名称(冗余)',
  `depot_id` bigint(20) DEFAULT NULL COMMENT '仓库ID',
  `depot_name` varchar(128) DEFAULT NULL COMMENT '仓库名称(冗余)',
  `qty` decimal(15,3) DEFAULT 0 COMMENT '批次当前数量',
  `unit` varchar(32) DEFAULT NULL COMMENT '单位',
  `production_date` date DEFAULT NULL COMMENT '生产日期',
  `shelf_life_days` int(11) DEFAULT NULL COMMENT '保质期(天)',
  `expire_date` date DEFAULT NULL COMMENT '到期日期',
  `supplier` varchar(128) DEFAULT NULL COMMENT '来源/供应商',
  `status` varchar(16) DEFAULT '在库' COMMENT '状态：在库/已出库/已过期',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `tenant_id` bigint(20) DEFAULT NULL COMMENT '租户ID',
  `delete_flag` varchar(1) DEFAULT '0' COMMENT '删除标记',
  PRIMARY KEY (`id`),
  KEY `idx_fb_material` (`material_id`),
  KEY `idx_fb_batch_no` (`batch_no`),
  KEY `idx_fb_expire` (`expire_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='批次与保质期台账';

-- 2) 菜单：插件中心 -> 批次与效期
INSERT INTO jsh_function(number,name,parent_number,url,component,state,sort,enabled,type,push_btn,icon,delete_flag)
SELECT '090023','批次与效期','0900','/plugin/foodbatch','/plugin/index',b'1','0523',b'1','电脑版',null,'calendar','0'
FROM dual WHERE NOT EXISTS (SELECT 1 FROM jsh_function WHERE url='/plugin/foodbatch' AND delete_flag<>'1');

-- 3) 角色授权：平台管理员(4) / 租户管理员(10)
SET @food_menu_id := (SELECT id FROM jsh_function WHERE number='090023' AND delete_flag<>'1' LIMIT 1);

UPDATE jsh_user_business
SET value = CONCAT(value, CONCAT('[', @food_menu_id, ']'))
WHERE type='RoleFunctions'
  AND key_id IN ('4','10')
  AND value IS NOT NULL
  AND @food_menu_id IS NOT NULL
  AND value NOT LIKE CONCAT('%[', @food_menu_id, ']%');

SELECT id, number, name, url FROM jsh_function WHERE number IN ('0900','090023') ORDER BY number;
SELECT key_id, type, LEFT(value, 60) AS role_functions_head FROM jsh_user_business WHERE type='RoleFunctions' AND key_id IN ('4','10');
