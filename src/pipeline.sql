-- Daily trip count and average fare from the built-in NYC taxi sample.
CREATE OR REFRESH MATERIALIZED VIEW daily_trips AS
SELECT
  DATE(tpep_pickup_datetime) AS trip_date,
  COUNT(*) AS trips,
  ROUND(AVG(fare_amount), 2) AS avg_fare
FROM samples.nyctaxi.trips
GROUP BY 1;
