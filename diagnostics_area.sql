/*
	sql_diagnostix
	Copyright Federico Razzoli  2013
	Contacts: santec [At) riseup d0t net
	
	sql_diagnostix is free software: you can redistribute it and/or modify
	it under the terms of the GNU Affero General Public License as published by
	the Free Software Foundation, version 3 of the License.
	
	sql_diagnostix is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU Affero General Public License for more details.
	
	You should have received a copy of the GNU Affero General Public License
	along with sql_diagnostix.  If not, see <http://www.gnu.org/licenses/>.
*/


DELIMITER ||

SET @@session.SQL_MODE = 'ERROR_FOR_DIVISION_BY_ZERO,NO_ZERO_DATE,NO_ZERO_IN_DATE,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION,ONLY_FULL_GROUP_BY,STRICT_ALL_TABLES,STRICT_TRANS_TABLES';

-- utility database
CREATE DATABASE IF NOT EXISTS `_`
	DEFAULT CHARACTER SET = 'utf8'
	DEFAULT COLLATE = 'utf8_general_ci';


DROP PROCEDURE IF EXISTS `_`.`materialize_diagnostics_area`;
CREATE PROCEDURE `_`.`materialize_diagnostics_area`()
	MODIFIES SQL DATA
	NOT DETERMINISTIC
	COMMENT 'Copy diagnostix into _.DIAGNOSTICS_AREA'
`whole_proc`:
BEGIN
	-- statement information
	DECLARE `n_errs`  TINYINT UNSIGNED  DEFAULT NULL;
	DECLARE `i`       TINYINT UNSIGNED  DEFAULT 1;
	
	-- data from individual conditions
	DECLARE `err_sqlstate`            CHAR(5)       DEFAULT '00000';
	DECLARE `err_no`                  SMALLINT UNSIGNED DEFAULT 0;
	DECLARE `err_message`             VARCHAR(128)  DEFAULT '';
	DECLARE `err_class_origin`        VARCHAR(64)   DEFAULT '';
	DECLARE `err_subclass_origin`     VARCHAR(64)   DEFAULT '';
	DECLARE `err_constraint_catalog`  VARCHAR(64)   DEFAULT '';
	DECLARE `err_constraint_schema`   VARCHAR(64)   DEFAULT '';
	DECLARE `err_constraint_name`     VARCHAR(64)   DEFAULT '';
	DECLARE `err_catalog_name`        VARCHAR(64)   DEFAULT '';
	DECLARE `err_schema_name`         VARCHAR(64)   DEFAULT '';
	DECLARE `err_table_name`          VARCHAR(64)   DEFAULT '';
	DECLARE `err_column_name`         VARCHAR(64)   DEFAULT '';
	DECLARE `err_cursor_name`         VARCHAR(64)   DEFAULT '';
	
	GET DIAGNOSTICS `n_errs` = NUMBER;
	-- if DA is empty, exit now
	IF NOT `n_errs` > 0 THEN
		LEAVE `whole_proc`;
	END IF;
	
	-- the outer query which will return ALL conditions
	SET @__stk__sql_stmt_super  = _utf8'',
	-- individual subqueries, which will return info about ONE condition
		@__stk__sql_stmt_sub    = _utf8'';
	
	-- loop on individual errors
	WHILE `i` <= `n_errs` DO
		-- get all info from current condition
		GET DIAGNOSTICS
			CONDITION `i`
			`err_sqlstate`            = RETURNED_SQLSTATE,
			`err_no`                  = MYSQL_ERRNO,
			`err_message`             = MESSAGE_TEXT,
			`err_class_origin`        = CLASS_ORIGIN,
			`err_subclass_origin`     = SUBCLASS_ORIGIN,
			`err_constraint_catalog`  = CONSTRAINT_CATALOG,
			`err_constraint_schema`   = CONSTRAINT_SCHEMA,
			`err_constraint_name`     = CONSTRAINT_NAME,
			`err_catalog_name`        = CATALOG_NAME,
			`err_schema_name`         = SCHEMA_NAME,
			`err_table_name`          = TABLE_NAME,
			`err_column_name`         = COLUMN_NAME,
			`err_cursor_name`         = CURSOR_NAME;
		
		-- compose the subquery which returns (as constants)
		-- current condition's data
		SELECT CONCAT(
				'SELECT ',
					`i`, ' AS `ID`, ',
					QUOTE(IFNULL(`err_sqlstate`, '')), ' AS `SQLSTATE`, ',
					`err_no`, ' AS `MYSQL_ERRNO`, ',
					QUOTE(IFNULL(`err_message`, '')), ' AS `MESSAGE_TEXT`, ',
					QUOTE(IFNULL(`err_class_origin`, '')), ' AS `CLASS_ORIGIN`, ',
					QUOTE(IFNULL(`err_subclass_origin`, '')), ' AS `SUBCLASS_ORIGIN`, ',
					QUOTE(IFNULL(`err_constraint_catalog`, '')), ' AS `CONSTRAINT_CATALOG`, ',
					QUOTE(IFNULL(`err_constraint_schema`, '')), ' AS `CONSTRAINT_SCHEMA`, ',
					QUOTE(IFNULL(`err_constraint_name`, '')), ' AS `CONSTRAINT_NAME`, ',
					QUOTE(IFNULL(`err_catalog_name`, '')), ' AS `CATALOG_NAME`, ',
					QUOTE(IFNULL(`err_schema_name`, '')), ' AS `SCHEMA_NAME`, ',
					QUOTE(IFNULL(`err_table_name`, '')), ' AS `TABLE_NAME`, ',
					QUOTE(IFNULL(`err_column_name`, '')), ' AS `COLUMN_NAME`, ',
					QUOTE(IFNULL(`err_cursor_name`, '')), ' AS `CURSOR_NAME`'
			)
			INTO  @__stk__sql_stmt_sub;
		
		IF `n_errs` > 1 THEN
			-- there are several conditions.
			-- each subquery must be within (parenthesis) and
			-- the subqueries need to be separated with UNION.
			SET  @__stk__sql_stmt_sub = CONCAT('(', @__stk__sql_stmt_sub, ')');
			IF `i` = 1 THEN
				SET  @__stk__sql_stmt_super = @__stk__sql_stmt_sub;
			ELSE
				SET  @__stk__sql_stmt_super = CONCAT(@__stk__sql_stmt_super, ' UNION ALL ', @__stk__sql_stmt_sub);
			END IF;
		ELSE
			-- there is only one condition.
			-- we'll just exec @__stk__sql_stmt_sub
			SET  @__stk__sql_stmt_super = @__stk__sql_stmt_sub;
		END IF;
		
		SET `i` = `i` + 1;
	END WHILE;
	
	-- this is our artificial diagnostics area
	DROP TABLE IF EXISTS `_`.`DIAGNOSTICS_AREA`;
	CREATE TABLE `_`.`DIAGNOSTICS_AREA`
	(
		`ID`                  TINYINT UNSIGNED   NOT NULL   COMMENT 'Condition position in DA',
		`SQLSTATE`            VARCHAR(5)    NOT NULL,
		`MYSQL_ERRNO`         SMALLINT UNSIGNED  NOT NULL,
		`MESSAGE_TEXT`        VARCHAR(128)  NOT NULL,
		`CLASS_ORIGIN`        VARCHAR(64)   NOT NULL,
		`SUBCLASS_ORIGIN`     VARCHAR(64)   NOT NULL,
		`CONSTRAINT_CATALOG`  VARCHAR(64)   NOT NULL,
		`CONSTRAINT_SCHEMA`   VARCHAR(64)   NOT NULL,
		`CONSTRAINT_NAME`     VARCHAR(64)   NOT NULL,
		`CATALOG_NAME`        VARCHAR(64)   NOT NULL,
		`SCHEMA_NAME`         VARCHAR(64)   NOT NULL,
		`TABLE_NAME`          VARCHAR(64)   NOT NULL,
		`COLUMN_NAME`         VARCHAR(64)   NOT NULL,
		`CURSOR_NAME`         VARCHAR(64)   NOT NULL
	)
		ENGINE = MEMORY,
		COMMENT 'Materialization of the DA';
	
	SET  @__stk__sql_stmt_super = CONCAT(
		'INSERT INTO `_`.`DIAGNOSTICS_AREA` ',
		@__stk__sql_stmt_super,
		';'
	);
	
	-- execute statement which populate _.DIAGNOSTICS_AREA
	PREPARE __stk__stmt FROM @__stk__sql_stmt_super;
	EXECUTE __stk__stmt;
	DEALLOCATE PREPARE __stk__stmt;
	
	-- reset user vars
	SET @__stk__sql_stmt_super  = NULL,
		@__stk__sql_stmt_sub    = NULL;
END;


DROP PROCEDURE IF EXISTS `_`.`show_diagnostics_area`;
CREATE PROCEDURE `_`.`show_diagnostics_area`()
	MODIFIES SQL DATA
	NOT DETERMINISTIC
	COMMENT 'SHOW commonly used info from diagnostix area'
BEGIN
	CALL `materialize_diagnostics_area`();
	SELECT
		`ID`, `SQLSTATE`, `MYSQL_ERRNO`, `MESSAGE_TEXT`
		FROM `_`.`DIAGNOSTICS_AREA`
		ORDER BY `ID`;
END;


DROP PROCEDURE IF EXISTS `_`.`show_full_diagnostics_area`;
CREATE PROCEDURE `_`.`show_full_diagnostics_area`()
	MODIFIES SQL DATA
	NOT DETERMINISTIC
	COMMENT 'SHOW diagnostics area'
BEGIN
	CALL `materialize_diagnostics_area`();
	SELECT *
		FROM `_`.`DIAGNOSTICS_AREA`
		ORDER BY `ID`;
END;


||
DELIMITER ;

COMMIT;
