-- +----------------------------------------------------------------------------+
-- |                          	  runanyun Mapele                               |
-- |                            wuyu.xiao@gmail.com                             |
-- |             http://mapele.coding.me/ && http://mapele.github.io/           |
-- |----------------------------------------------------------------------------|
-- | DATABASE : Oracle 11g(RAC)                                                 |
-- | FILE     : awr_top_timed_events.sql                                        |
-- | PURPOSE  : 通过元数据获取AWR中连续快照间的Top Timed Events报告.            |
-- +----------------------------------------------------------------------------+

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET VER OFF
SET FEEDBACK OFF

COLUMN PCT           FORMAT a15              HEADING 'PCT of DB TIMES'
COLUMN EVENT         FORMAT a40              HEADING 'EVENT'
COLUMN TIMES         FORMAT 999,999,990.99   HEADING 'TIMES(S)'
COLUMN INST_NO       FORMAT 99          	 HEADING 'INSNO'
COLUMN SNAP_ID       FORMAT 9999999      	 HEADING 'SNAP_ID'

PROMPT
BREAK ON INST_NO skip page

ACCEPT DAYS 		 number PROMPT "ENTER latest snap days: " default 7

SELECT INSTANCE_NUMBER INST_NO,
       SNAP_ID, 
	   TO_CHAR(BEGIN_INTERVAL_TIME,'YYYY-MM-DD HH24:MI:SS') BEGIN_INTERVAL_TIME
  FROM DBA_HIST_SNAPSHOT
 WHERE BEGIN_INTERVAL_TIME > TRUNC(SYSDATE) - &DAYS
 ORDER BY INSTANCE_NUMBER,BEGIN_INTERVAL_TIME;

PROMPT 

ACCEPT INST_NO 		   number PROMPT "ENTER INSTANCE_NUMBER: " default 0
ACCEPT BEGIN_SNAP 	   number PROMPT "ENTER BEGIN_SNAP: "
ACCEPT END_SNAP   	   number PROMPT "ENTER END_SNAP: "
COMPUTE sum of TIMES on SNAP_ID

PROMPT
PROMPT Listing top timed events by instance no and snap id ...
BREAK ON INST_NO ON SNAP_ID skip page

SELECT A.INST_NO
      ,TO_CHAR(B.BEGIN_INTERVAL_TIME, 'mmdd hh24mi') SNAP_TIME
      ,A.SNAP_ID
      ,A.EVENT
      ,A.PCT || '%' PCT
      ,A.TIMES
  FROM (SELECT INSTANCE_NUMBER INST_NO
              ,SNAP_ID-1 SNAP_ID
              ,EVENT
              ,ROUND(TIMES,2) TIMES
              ,ROUND(RATIO_TO_REPORT(TIMES) OVER(PARTITION BY SNAP_ID) * 100,2) PCT
          FROM (SELECT INSTANCE_NUMBER
                      ,'DB CPU' EVENT
                      ,SNAP_ID
                      ,VALUE / 1E6 - LAG(VALUE) OVER(PARTITION BY INSTANCE_NUMBER, STAT_NAME ORDER BY SNAP_ID) / 1E6 TIMES
                  FROM DBA_HIST_SYS_TIME_MODEL
                 WHERE STAT_NAME = 'DB CPU'
				   AND INSTANCE_NUMBER= CASE WHEN &INST_NO = 0 THEN INSTANCE_NUMBER ELSE &INST_NO END
                   AND SNAP_ID BETWEEN &BEGIN_SNAP AND &END_SNAP
                UNION ALL
                SELECT INSTANCE_NUMBER
                      ,'cpu on queue time' EVENT
                      ,SNAP_ID
                      ,NVL(VALUE, 0) / 100 VALUE
                  FROM DBA_HIST_OSSTAT T
                 WHERE STAT_NAME = 'RSRC_MGR_CPU_WAIT_TIME'
                   AND INSTANCE_NUMBER= CASE WHEN &INST_NO = 0 THEN INSTANCE_NUMBER ELSE &INST_NO END
                   AND SNAP_ID BETWEEN &BEGIN_SNAP AND &END_SNAP
                UNION ALL
                SELECT INSTANCE_NUMBER
                      ,EVENT_NAME
                      ,SNAP_ID
                      ,TIME_WAITED_MICRO_FG / 1E6 -
                       LAG(TIME_WAITED_MICRO_FG) OVER(PARTITION BY INSTANCE_NUMBER, EVENT_NAME ORDER BY SNAP_ID) / 1E6
                  FROM DBA_HIST_SYSTEM_EVENT
                 WHERE WAIT_CLASS != 'Idle'
                   AND INSTANCE_NUMBER= CASE WHEN &INST_NO = 0 THEN INSTANCE_NUMBER ELSE &INST_NO END
                   AND SNAP_ID BETWEEN &BEGIN_SNAP AND &END_SNAP)
         WHERE TIMES > 0) A
      ,DBA_HIST_SNAPSHOT B
 WHERE PCT > 1
   AND A.SNAP_ID = B.SNAP_ID
   AND A.INST_NO = B.INSTANCE_NUMBER
   AND A.SNAP_ID != &BEGIN_SNAP-1
   AND event != 'cpu on queue time'
 ORDER BY A.INST_NO
         ,SNAP_ID
         ,TIMES DESC;