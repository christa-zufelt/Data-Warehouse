
ALTER PROCEDURE [RPT].BuildCalendar AS

/* Created by Christa Zufelt 9/7/17	| last updated 10/2/17 to run daily
	Build Calendar dimension in RPT schema  */


BEGIN

DROP TABLE RPT.Calendar;

DECLARE @StartDate DATE = '19000701', @NumberOfYears INT = 150;

-- prevent set or regional settings from interfering with 
-- interpretation of dates / literals

SET DATEFIRST 7;
SET DATEFORMAT mdy;
SET LANGUAGE US_ENGLISH;

IF OBJECT_ID('tempdb..#dim') IS NOT NULL
    DROP TABLE #dim
IF OBJECT_ID('tempdb..#date') IS NOT NULL
    DROP TABLE #date

--- need confirmation on first day of week - is week reporting Sunday-Saturday, or Monday-Sunday?

DECLARE @CutoffDate DATE = DATEADD(YEAR, @NumberOfYears, @StartDate);

-- this is just a holding table for intermediate calculations:
--drop table #dim
CREATE TABLE #dim
(
  [Date]       DATE PRIMARY KEY, 
  DateKey     AS CONVERT(CHAR(8),   [date], 112),
  [Day]        AS DATEPART(DAY,      [date]),
  [Month]      AS DATEPART(MONTH,    [date]),
  [Year]       AS DATEPART(YEAR,     [date]),
  FirstOfMonth AS CONVERT(DATE, DATEADD(MONTH, DATEDIFF(MONTH, 0, [date]), 0)),
  [MonthDesc]  AS DATENAME(MONTH,    [date]),
  FirstOfWeek AS CONVERT(DATE, DATEADD(WEEK, DATEDIFF(WEEK, 0, [date]), -1)),
  [DayOfWeek]  AS DATEPART(WEEKDAY,  [date]),
  [DayOfWeekDesc]  AS DATENAME(WEEKDAY,  [date]),
  [FiscalQuarter]    AS DATEPART(QUARTER,  [date]),
  FirstOfQuarter  AS CONVERT(DATE, DATEADD(QUARTER,  DATEDIFF(QUARTER,  0, [date]), 0)),
  [FiscalYear]       AS DATEPART(YEAR,     [date]),
  FirstDayOfYear  AS CONVERT(DATE, DATEADD(YEAR,  DATEDIFF(YEAR,  0, [date]), 0))
);

-- use the catalog views to generate as many rows as we need

INSERT #dim([date]) 
SELECT d
FROM
(
  SELECT d = DATEADD(DAY, rn - 1, @StartDate)
  FROM 
  (
    SELECT TOP (DATEDIFF(DAY, @StartDate, @CutoffDate)) 
      rn = ROW_NUMBER() OVER (ORDER BY s1.[object_id])
    FROM sys.all_objects AS s1
    CROSS JOIN sys.all_objects AS s2
    -- on my system this would support > 5 million days
    ORDER BY s1.[object_id]
  ) AS x
) AS y;

---- Add fields to calculate holidays
ALTER TABLE #dim
  ADD [DOWInMonth] TINYINT,
	IsHoliday BIT DEFAULT 0,
	HolidayDesc VARCHAR(255),
	FirstDayOfFiscalYear DATE;

--- Holiday calculations part 1: define day of week in month (e.g. 4th Thursday
UPDATE #dim set #dim.[DOWInMonth] = updt.[DOWInMonth]
FROM  
(
    SELECT CONVERT(TINYINT, ROW_NUMBER() OVER 
                  (PARTITION BY FirstOfMonth, [DayOfWeek] ORDER BY [date])) [DOWInMonth], [DATE]
    FROM #dim
) AS updt
WHERE #dim.[DATE] = updt.[DATE];


---- Holiday calcs part 2:  
;WITH x AS 
(
  SELECT DateKey, [Date], IsHoliday, HolidayDesc, FirstDayOfYear,
    DOWInMonth, [MonthDesc], [DayofWeekDesc], [Day],
    LastDOWInMonth = ROW_NUMBER() OVER 
    (
      PARTITION BY FirstOfMonth, DayOfWeek 
      ORDER BY [Date] DESC
    )
  FROM #dim
)
UPDATE x SET IsHoliday = 1, HolidayDesc = CASE
  WHEN ([Date] = FirstDayOfYear) 
    THEN 'New Year''s Day'
  WHEN ([DOWInMonth] = 3 AND [MonthDesc] = 'January' AND [DayofWeekDesc] = 'Monday')
    THEN 'Martin Luther King Day'    -- (3rd Monday in January)
  WHEN ([DOWInMonth] = 3 AND [MonthDesc] = 'February' AND [DayofWeekDesc] = 'Monday')
    THEN 'President''s Day'          -- (3rd Monday in February)
  WHEN ([LastDOWInMonth] = 1 AND [MonthDesc] = 'May' AND [DayofWeekDesc] = 'Monday')
    THEN 'Memorial Day'              -- (last Monday in May)
  WHEN ([MonthDesc] = 'July' AND [Day] = 4)
    THEN 'Independence Day'          -- (July 4th)
  WHEN ([DOWInMonth] = 1 AND [MonthDesc] = 'September' AND [DayofWeekDesc] = 'Monday')
    THEN 'Labour Day'                -- (first Monday in September)
  WHEN ([DOWInMonth] = 2 AND [MonthDesc] = 'October' AND [DayofWeekDesc] = 'Monday')
    THEN 'Columbus Day'              -- Columbus Day (second Monday in October)
  WHEN ([MonthDesc] = 'November' AND [Day] = 11)
    THEN 'Veterans'' Day'            -- Veterans' Day (November 11th)
  WHEN ([DOWInMonth] = 4 AND [MonthDesc] = 'November' AND [DayofWeekDesc] = 'Thursday')
    THEN 'Thanksgiving Day'          -- Thanksgiving Day (fourth Thursday in November)
  WHEN ([MonthDesc] = 'December' AND [Day] = 25)
    THEN 'Christmas Day'
  END
WHERE 
  ([Date] = FirstDayOfYear)
  OR ([DOWInMonth] = 3     AND [MonthDesc] = 'January'   AND [DayofWeekDesc] = 'Monday')
  OR ([DOWInMonth] = 3     AND [MonthDesc] = 'February'  AND [DayofWeekDesc] = 'Monday')
  OR ([LastDOWInMonth] = 1 AND [MonthDesc] = 'May'       AND [DayofWeekDesc] = 'Monday')
  OR ([MonthDesc] = 'July' AND [Day] = 4)
  OR ([DOWInMonth] = 1     AND [MonthDesc] = 'September' AND [DayofWeekDesc] = 'Monday')
  OR ([DOWInMonth] = 2     AND [MonthDesc] = 'October'   AND [DayofWeekDesc] = 'Monday')
  OR ([MonthDesc] = 'November' AND [Day] = 11)
  OR ([DOWInMonth] = 4     AND [MonthDesc] = 'November' AND [DayofWeekDesc] = 'Thursday')
  OR ([MonthDesc] = 'December' AND [Day] = 25);



--- need to update isholiday to 0 when null
UPDATE #dim 
SET IsHoliday = 0
WHERE IsHoliday IS NULL;
  



--drop table SUMMIT.Calendar
CREATE TABLE [RPT].Calendar   
	( [Date] DATE PRIMARY KEY 
	, [DateKey]  INT 
	, [Day] TINYINT
	, [Month] TINYINT
	, [Year] SMALLINT
	, [FirstOfMonth] DATE
	, [MonthDesc] VARCHAR(20)
	, [FiscalMonth] TINYINT
	, [FirstOfWeek] DATE
	, [DayOfWeek] TINYINT
	, [DayOfWeekDesc] VARCHAR(10)
	, [FirstOfFiscalQuarter] DATE
	, [FiscalQuarter] TINYINT
	, [FiscalQuarterDesc] VARCHAR(2)	
	, [FiscalYear] SMALLINT
	, [FiscalYearDesc] VARCHAR(4)
	, [FirstOfFiscalYear] DATE
	, [IsHoliday] BIT
	, [HolidayDesc] VARCHAR(50)
	, [AdjustedFiscalYear] INT
	)
	;



INSERT INTO [RPT].Calendar 
SELECT [Date]
	, [DateKey]
	, [Day]
	, [Month]
	, [Year]
	, [FirstOfMonth]
	, [MonthDesc]
	, CASE WHEN [Month] = 7 THEN 1
		WHEN [Month] = 8 THEN 2   
		WHEN [Month] = 9 THEN 3
		WHEN [Month] = 10 THEN 4
		WHEN [Month] = 11 THEN 5
		WHEN [Month] = 12 THEN 6
		WHEN [Month] = 1 THEN 7
		WHEN [Month] = 2 THEN 8
		WHEN [Month] = 3 THEN 9
		WHEN [Month] = 4 THEN 10
		WHEN [Month] = 5 THEN 11
		WHEN [Month] = 6 THEN 12 END as FiscalMonth
	, [FirstOfWeek]
	, [DayOfWeek]
	, [DayofWeekDesc]
	, CASE WHEN [Month]IN (7,10,1,4) THEN FirstOfMonth 
		WHEN [Month] IN (8,11,2,5) THEN DATEADD(month, -1, FirstOfMonth)
		WHEN [Month] IN (9,12,3,6) THEN DATEADD(month, -2, FirstOfMonth)
		END as [FirstOfFiscalQuarter]
	, CASE WHEN [Month] IN (7,8,9) THEN 1
		WHEN [Month] IN (10,11,12) THEN 2
		WHEN [Month] IN (1,2,3) THEN 3
		WHEN [Month] IN (4,5,6) THEN 4
		END as [FiscalQuarter]
	, CASE WHEN [Month] IN (7,8,9) THEN 'Q1'  
		WHEN [Month] IN (10,11,12) THEN 'Q2'
		WHEN [Month] IN (1,2,3) THEN 'Q3'
		WHEN [Month] IN (4,5,6) THEN 'Q4'
		END as [FiscalQuarterDesc]	
	, CASE WHEN [Month] >= 7 THEN [YEAR] + 1 ELSE [YEAR] END as [FiscalYear]
	, CASE WHEN [Month] >= 7 THEN 'FY' + SUBSTRING(CONVERT(VARCHAR(4),[YEAR] + 1),3,2) 
		ELSE 'FY' + SUBSTRING(CONVERT(VARCHAR(4),[YEAR]),3,2) END as [FiscalYearDesc]
	, CASE WHEN [Month] = 7 THEN FirstOfMonth
		WHEN [Month] = 8 THEN DATEADD(month, -1, FirstOfMonth)
		WHEN [Month] = 9 THEN DATEADD(month, -2, FirstOfMonth)
		WHEN [Month] = 10 THEN DATEADD(month, -3, FirstOfMonth)
		WHEN [Month] = 11 THEN DATEADD(month, -4, FirstOfMonth)
		WHEN [Month] = 12 THEN DATEADD(month, -5, FirstOfMonth)
		WHEN [Month] = 1 THEN DATEADD(month, -6, FirstOfMonth)
		WHEN [Month] = 2 THEN DATEADD(month, -7, FirstOfMonth)
		WHEN [Month] = 3 THEN DATEADD(month, -8, FirstOfMonth)
		WHEN [Month] = 4 THEN DATEADD(month, -9, FirstOfMonth)
		WHEN [Month] = 5 THEN DATEADD(month, -10, FirstOfMonth)
		WHEN [Month] = 6 THEN DATEADD(month, -11, FirstOfMonth) END as FirstOfFiscalYear
	, [IsHoliday]
	, [HolidayDesc]  
--- add adj column that shows how many years we are away from current fiscal year, current year status is based on CNTRL_INFO record
	, CASE WHEN [Month] >= 7 THEN [YEAR] + 1 - (SELECT LEFT(CI.CNTL_INFO,4) + 1 AS 'FY'
												FROM UHELP.CNTL_INFO AS CI
												WHERE CI.CNTL_KEY = 'CNTRBCURRFISCALYEAR')
		ELSE [YEAR] - (SELECT LEFT(CI.CNTL_INFO,4) + 1 AS 'FY'
												FROM UHELP.CNTL_INFO AS CI
												WHERE CI.CNTL_KEY = 'CNTRBCURRFISCALYEAR')
		END as AdjustedFiscalYear

-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------

FROM #dim
ORDER BY [Date]




------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------
------------------------ Create Fiscal Day to enable YoY calculations --------------------------
------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------
ALTER TABLE RPT.Calendar
  ADD FiscalDay SMALLINT;


--- Update FiscalDay in Calendar (Exclude Feb 29th from Rowcount)
UPDATE RPT.Calendar set RPT.Calendar.FiscalDay = updt.FiscalDay
FROM  
(
    SELECT CONVERT(SMALLINT, ROW_NUMBER() OVER 
                  (PARTITION BY FirstOfFiscalYear ORDER BY [date])) FiscalDay, [DATE]
    FROM RPT.Calendar
	WHERE CONVERT(VARCHAR,[Month])+'-'+CONVERT(VARCHAR,[Day]) <> '2-29' 
) AS updt
WHERE RPT.Calendar.[DATE] = updt.[DATE];


----- Set Feb 29th = Fiscal Day 243 (Feb 28th)
UPDATE RPT.Calendar set RPT.Calendar.FiscalDay = updt.FiscalDay
FROM  
(
    SELECT 243 as FiscalDay, [DATE]
    FROM RPT.Calendar
	WHERE CONVERT(VARCHAR,[Month])+'-'+CONVERT(VARCHAR,[Day]) = '2-29' 
) AS updt
WHERE RPT.Calendar.[DATE] = updt.[DATE];





-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------



drop table #dim

END






