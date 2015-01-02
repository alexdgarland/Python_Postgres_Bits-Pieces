﻿
CREATE SCHEMA IF NOT EXISTS staging AUTHORIZATION postgres;

DROP TABLE IF EXISTS staging."JCMB_Weather_Loads" CASCADE;
DROP TYPE IF EXISTS load_state;
CREATE TYPE load_state AS ENUM ('initialised', 'in progress', 'files staged', 'completed okay', 'failed');
CREATE TABLE staging."JCMB_Weather_Loads"
	(
	"load_id"		serial,
	"load_start_timestamp"	timestamp without time zone NOT NULL,
	"load_latest_state"	load_state NOT NULL DEFAULT 'initialised',
	"load_end_timestamp"	timestamp without time zone
	)
WITH (OIDS=FALSE);
ALTER TABLE staging."JCMB_Weather_Loads" OWNER TO postgres;
ALTER TABLE staging."JCMB_Weather_Loads" ADD CONSTRAINT PK_JCMB_Weather_Loads PRIMARY KEY ("load_id");


CREATE OR REPLACE FUNCTION staging."AssignAndGetNewLoadID"()
RETURNS integer
AS
'INSERT INTO staging."JCMB_Weather_Loads"("load_start_timestamp") VALUES (clock_timestamp()) RETURNING load_id;'
LANGUAGE SQL;

DROP TABLE IF EXISTS staging."JCMB_Weather_LoadFiles" CASCADE;
DROP TYPE IF EXISTS file_state;
CREATE TYPE file_state AS ENUM ('registered', 'staging started', 'staging complete', 'loaded');
CREATE TABLE staging."JCMB_Weather_LoadFiles"
	(
	"file_id"			serial NOT NULL,
	"source_file_name"		character varying(1000) NOT NULL,
	"source_file_modified_datetime"	timestamp without time zone NOT NULL,
	"downloaded_file_name"		character varying(1000) NOT NULL,
	"load_id"			integer NOT NULL,
	"file_registered_timestamp"	timestamp without time zone NOT NULL DEFAULT clock_timestamp(),
	"file_latest_state"		file_state NOT NULL DEFAULT 'registered',		
	"file_load_complete_timestamp"	timestamp without time zone
	)
WITH (OIDS=FALSE);
ALTER TABLE staging."JCMB_Weather_LoadFiles" OWNER TO postgres;
ALTER TABLE staging."JCMB_Weather_LoadFiles" ADD CONSTRAINT PK_JCMB_Weather_LoadFiles PRIMARY KEY("file_id");
ALTER TABLE staging."JCMB_Weather_LoadFiles" ADD CONSTRAINT UQ_JCMB_Weather_LoadFiles__Name_ModifiedDate
	UNIQUE("source_file_name", "source_file_modified_datetime");
ALTER TABLE staging."JCMB_Weather_LoadFiles" ADD CONSTRAINT FK_JCMB_Weather_LoadFiles__LoadID FOREIGN KEY("load_id")
	REFERENCES staging."JCMB_Weather_Loads"("load_id");


DROP TABLE IF EXISTS staging."JCMB_Weather_Staging" CASCADE;
CREATE TABLE staging."JCMB_Weather_Staging"
    (
    "staged_row_id"			serial,
    "file_id"				integer NOT NULL,
    "date_time_text_source"             character varying (500),
    "atmospheric_pressure_mbar"         character varying (500),
    "rainfall_mm"                       character varying (500),
    "wind_speed_m_per_s"                character varying (500),
    "wind_direction_degrees"            character varying (500),
    "surface_temperature_c"             character varying (500),
    "relative_humidity_percentage"      character varying (500),
    "solar_flux_kw_per_m2"             	character varying (500),
    "battery_v"                         character varying (500)
    )
WITH (OIDS=FALSE);
ALTER TABLE staging."JCMB_Weather_Staging" OWNER TO postgres;
ALTER TABLE staging."JCMB_Weather_Staging" ADD CONSTRAINT "PK_JCMB_Weather_Staging" PRIMARY KEY ("staged_row_id");


CREATE OR REPLACE VIEW staging."JCMB_Weather_Staging_Summary"
AS
	SELECT	LEFT(date_time_text_source, 10) AS DayOfReading,
		COUNT(*)
	FROM 	staging."JCMB_Weather_Staging"
	GROUP BY LEFT(date_time_text_source, 10)
	ORDER BY DayOfReading DESC;
COMMENT ON VIEW staging."JCMB_Weather_Staging_Summary" IS 'Summary view for manual load checking.';


DROP TABLE IF EXISTS public."JCMB_Weather_Data";
CREATE TABLE public."JCMB_Weather_Data"
    (
    "date_time"				timestamp without time zone 	NOT NULL,
    "atmospheric_pressure_mbar"         integer                     	NOT NULL,
    "rainfall_mm"                       numeric(15,3)			NOT NULL,
    "wind_speed_m_per_s"                numeric(15,3)               	NOT NULL,
    "wind_direction_degrees"            numeric(15,3)               	NOT NULL,           
    "surface_temperature_c"             numeric(15,3)               	NOT NULL,
    "relative_humidity_percentage"      numeric(15,3)               	NOT NULL,
    "solar_flux_kw_per_m2"             	numeric(15,3)			NOT NULL,
    "battery_v"                         numeric(15,3)               	NOT NULL,
    "file_id_created"			integer				NOT NULL,
    "file_id_last_updated"			integer				NOT NULL
    );
ALTER TABLE public."JCMB_Weather_Data"  OWNER TO postgres;
ALTER TABLE public."JCMB_Weather_Data" ADD CONSTRAINT PK_JCMB_Weather_Data PRIMARY KEY ("date_time");


CREATE OR REPLACE FUNCTION staging."Convert_WeatherReading_DateTime"(date_time character varying(500))
RETURNS timestamp without time zone
AS
$BODY$
BEGIN
	RETURN
		CASE WHEN SUBSTRING(date_time, 12, 2) = '24' THEN
			CAST(SUBSTRING(date_time, 1, 10) AS timestamp without time zone) + CAST('1 day' AS interval)
	ELSE	CAST(date_time AS timestamp without time zone)
	END;
END
$BODY$
LANGUAGE PLPGSQL;
COMMENT ON FUNCTION staging."Convert_WeatherReading_DateTime"(character varying(500))
IS 'Converts from text treating midnight as 24:00 in previous day, to standard timestamp treating it as 00:00 the next.';

-- Unit test for date conversion
WITH CTE_Setup ("Input Value", "Expected Output")
AS	(
	-- Value that doesn't need converting other than a straight CAST
	SELECT '2013/01/01 23:00', CAST('2013/01/01 23:00' AS timestamp without time zone) UNION ALL
	-- Value where hour = 24 so day needs incrementing by one and hour setting to zero
	SELECT '2013/01/01 24:00', CAST('2013/01/02 00:00' AS timestamp without time zone) UNION ALL
	-- Value where incrementing the day will roll us into a new month and year
	SELECT '2013/12/31 24:00', CAST('2014/01/01 00:00' AS timestamp without time zone)
	)
,CTE_Process
AS	(
	SELECT 	"Input Value",
		"Expected Output",
		staging."Convert_WeatherReading_DateTime"("Input Value") AS "Actual Output"
		,CASE
			WHEN staging."Convert_WeatherReading_DateTime"("Input Value") = "Expected Output" THEN 'Success'
			ELSE '!!! FAILURE !!!'
		END AS "Test Result"
	FROM 	CTE_Setup
	)
SELECT	*
FROM 	CTE_Process
WHERE	"Test Result" = '!!! FAILURE !!!';


CREATE OR REPLACE VIEW staging."JCMB_Weather_Staging_Conversions"
AS
	SELECT	ConvertAndRank.date_time
		,ConvertAndRank.atmospheric_pressure_mbar
		,ConvertAndRank.rainfall_mm
		,ConvertAndRank.wind_speed_m_per_s
		,ConvertAndRank.wind_direction_degrees
		,ConvertAndRank.surface_temperature_c
		,ConvertAndRank.relative_humidity_percentage
		,ConvertAndRank.solar_flux_kw_per_m2
		,ConvertAndRank.battery_v
		,ConvertAndRank.file_id
		,lf.load_id
	FROM	(
		SELECT	staging."Convert_WeatherReading_DateTime"(date_time_text_source)	AS date_time
			,CAST(atmospheric_pressure_mbar AS integer)				AS atmospheric_pressure_mbar
			,CAST(rainfall_mm AS numeric(15,3))					AS rainfall_mm
			,CAST(wind_speed_m_per_s AS numeric(15,3))				AS wind_speed_m_per_s
			,CAST(wind_direction_degrees AS numeric(15,3))				AS wind_direction_degrees
			,CAST(surface_temperature_c AS numeric(15,3))				AS surface_temperature_c
			,CAST(relative_humidity_percentage AS numeric(15,3))			AS relative_humidity_percentage
			,CAST(solar_flux_kw_per_m2 AS numeric(15,3))				AS solar_flux_kw_per_m2
			,CAST(battery_v AS numeric(15,3))					AS battery_v
			,file_id
			,ROW_NUMBER() OVER
				(
				PARTITION BY staging."Convert_WeatherReading_DateTime"(date_time_text_source)
				ORDER BY CASE WHEN atmospheric_pressure_mbar LIKE '-%' THEN 1 ELSE 0 END, staged_row_id
				/* Negative atmospheric pressure readings seem to be bad data so want to use them only if we have no alternative */
				) AS LoadRanking
		FROM 	staging."JCMB_Weather_Staging"
		) AS ConvertAndRank
		INNER JOIN staging."JCMB_Weather_LoadFiles" AS lf
		ON lf.file_id = ConvertAndRank.file_id
	WHERE	ConvertAndRank.LoadRanking = 1;
COMMENT ON VIEW staging."JCMB_Weather_Staging_Conversions"
IS 'Handle type conversions in a single place to aid clean upsert in proc.  Also removes duplicates in source data.';


/*
Postgres doesn't currently have a single MERGE or UPSERT statement
so will have to do load to public table in two steps
*/

CREATE OR REPLACE FUNCTION staging."Update_Existing_Weather_Data"(load_id_to_process int)
RETURNS integer
AS
$BODY$
BEGIN
	UPDATE	public."JCMB_Weather_Data" AS d
	SET	atmospheric_pressure_mbar 	= s.atmospheric_pressure_mbar
		,rainfall_mm 			= s.rainfall_mm
		,wind_speed_m_per_s 		= s.wind_speed_m_per_s
		,wind_direction_degrees		= s.wind_direction_degrees
		,surface_temperature_c		= s.surface_temperature_c
		,relative_humidity_percentage	= s.relative_humidity_percentage
		,solar_flux_kw_per_m2		= s.solar_flux_kw_per_m2
		,battery_v			= s.battery_v
		,file_id_last_updated		= s.file_id
	FROM	staging."JCMB_Weather_Staging_Conversions" AS s
	WHERE	s.date_time = d.date_time
	AND	s.load_id = load_id_to_process
	/* Return key details so can do more detailed audit logging */
	RETURNING s.date_time, s.file_id;
END
$BODY$
LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION staging."Insert_New_Weather_Data"(load_id_to_process int)
RETURNS integer
AS
$BODY$
BEGIN
	INSERT INTO public."JCMB_Weather_Data"
		(
		date_time
		,atmospheric_pressure_mbar
		,rainfall_mm
		,wind_speed_m_per_s
		,wind_direction_degrees
		,surface_temperature_c
		,relative_humidity_percentage
		,solar_flux_kw_per_m2
		,battery_v
		,file_id_created
		,file_id_last_updated
		)
	SELECT	s.date_time
		,s.atmospheric_pressure_mbar
		,s.rainfall_mm
		,s.wind_speed_m_per_s
		,s.wind_direction_degrees
		,s.surface_temperature_c
		,s.relative_humidity_percentage
		,s.solar_flux_kw_per_m2
		,s.battery_v
		,s.file_id
		,s.file_id
	FROM	staging."JCMB_Weather_Staging_Conversions" AS s
		LEFT OUTER JOIN public."JCMB_Weather_Data" AS d
		ON s.date_time = d.date_time
	WHERE	d.date_time IS NULL
	AND	s.load_id = load_id_to_process
	/* Return key details so can do more detailed audit logging */
	RETURNING date_time, file_id_created;
END
$BODY$
LANGUAGE PLPGSQL;