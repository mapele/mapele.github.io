-- +----------------------------------------------------------------------------+
-- |                          	  runanyun Mapele                               |
-- |                            wuyu.xiao@gmail.com                             |
-- |             http://mapele.coding.me/ && http://mapele.github.io/           |
-- |----------------------------------------------------------------------------|
-- | DATABASE : Oracle 11g(RAC)                                                 |
-- | FILE     : awr_load_profile.sql                                            |
-- | PURPOSE  : 通过元数据获取AWR中连续快照间的load profile报告.                |
-- +----------------------------------------------------------------------------+

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET VER OFF
set LINESIZE 200
SET FEEDBACK OFF

COLUMN INST_NO       FORMAT 99          	    HEADING 'INSNO'
COLUMN SNAP_ID       FORMAT 99999
COLUMN "DB time"     FORMAT 999,999,999,999
COLUMN "DB CPU"      FORMAT 9,999,999,999
COLUMN Redo          FORMAT 999,999,999
COLUMN LogicalR      FORMAT 99,999,999 
COLUMN BlockChs      FORMAT 99,999,999
COLUMN Phyr          FORMAT 99,999 
COLUMN Phyw          FORMAT 9,999,999
COLUMN Calls         FORMAT 9,999,999
COLUMN Parses        FORMAT 999,999
COLUMN HParses       FORMAT 9,999
COLUMN Logons        FORMAT 999,999
COLUMN Execs         FORMAT 9,999,999
COLUMN Rbacks        FORMAT 9,999
COLUMN Trans         FORMAT 999,999

PROMPT
BREAK ON INST_NO skip page

ACCEPT DAYS 		 NUMBER PROMPT "ENTER latest snap days: " default 7

SELECT INSTANCE_NUMBER INST_NO,
       SNAP_ID, 
	   TO_CHAR(BEGIN_INTERVAL_TIME,'YYYY-MM-DD HH24:MI:SS') BEGIN_INTERVAL_TIME
  FROM DBA_HIST_SNAPSHOT
 WHERE BEGIN_INTERVAL_TIME > TRUNC(SYSDATE) - &DAYS
 ORDER BY INSTANCE_NUMBER,BEGIN_INTERVAL_TIME;

PROMPT 

ACCEPT INST_NO 		   NUMBER PROMPT "ENTER INSTANCE_NUMBER: " default 0
ACCEPT BEGIN_SNAP 	   NUMBER PROMPT "ENTER BEGIN_SNAP: "
ACCEPT END_SNAP   	   NUMBER PROMPT "ENTER END_SNAP: "

PROMPT
PROMPT Listing load profile by instance no and snap id ...

SELECT *
  FROM (SELECT TO_CHAR(HS.BEGIN_INTERVAL_TIME, 'mmdd hh24mi') SNAP_TIME
              ,S.*
          FROM (SELECT T.INSTANCE_NUMBER INST_NO
                      ,T.SNAP_ID - 1 SNAP_ID
                      ,STAT_NAME
                      ,NVL(VALUE - LAG(VALUE)
                           OVER(PARTITION BY T.INSTANCE_NUMBER
                               ,STAT_NAME ORDER BY T.INSTANCE_NUMBER
                               ,T.SNAP_ID)
                          ,0) VALUE
                  FROM DBA_HIST_SYS_TIME_MODEL T
                 WHERE INSTANCE_NUMBER= CASE WHEN &INST_NO = 0 THEN INSTANCE_NUMBER ELSE &INST_NO END
				   AND SNAP_ID BETWEEN &BEGIN_SNAP AND &END_SNAP
                   AND STAT_NAME IN ('DB time', 'DB CPU')
                UNION ALL
                SELECT T.INSTANCE_NUMBER INST
                      ,T.SNAP_ID - 1 SNAP_ID
                      ,STAT_NAME
                      ,NVL(VALUE - LAG(VALUE)
                           OVER(PARTITION BY T.INSTANCE_NUMBER
                               ,STAT_NAME ORDER BY T.INSTANCE_NUMBER
                               ,T.SNAP_ID)
                          ,0) VALUE
                  FROM DBA_HIST_SYSSTAT T
                 WHERE INSTANCE_NUMBER= CASE WHEN &INST_NO = 0 THEN INSTANCE_NUMBER ELSE &INST_NO END
				   AND SNAP_ID BETWEEN &BEGIN_SNAP AND &END_SNAP
                   AND STAT_NAME IN ('redo size'
                                    ,'session logical reads'
                                    ,'db block changes'
                                    ,'physical reads'
                                    ,'physical writes'
                                    ,'user calls'
                                    ,'parse count (total)'
                                    ,'parse count (hard)'
                                    ,'logons cumulative'
                                    ,'execute count'
                                    ,'user rollbacks'
                                    ,'user commits')) S
              ,DBA_HIST_SNAPSHOT HS
         WHERE S.SNAP_ID = HS.SNAP_ID
		   AND S.SNAP_ID != &BEGIN_SNAP-1)
PIVOT(SUM(VALUE)
   FOR STAT_NAME IN('DB time' AS "DB time"
                    ,'DB CPU' AS "DB CPU"
                    ,'redo size' AS "Redo"
                    ,'session logical reads' AS "LogicalR"
                    ,'db block changes' AS "BlockChs"
                    ,'physical reads' AS "Phyr"
                    ,'physical writes' AS "Phyw"
                    ,'user calls' AS "Calls"
                    ,'parse count (total)' AS "Parses"
                    ,'parse count (hard)' AS "HParses"
                    ,'logons cumulative' AS "Logons"
                    ,'execute count' AS "Execs"
                    ,'user rollbacks' AS "Rbacks"
                    ,'user commits' AS "Trans"))
 ORDER BY INST_NO
         ,SNAP_TIME;
