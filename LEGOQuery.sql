#This file was used in MySQL to query an open source LEGO database found at https://www.kaggle.com/datasets/rtatman/lego-database
#NOTE: Because the inventory_parts dataset of the database was originally humongous, the decision was made to limit the exploration to 1000 databases
#INVENTORY: a group of parts, possibly included in many different SETS
#Code Author: Winter Goodman
#1. In what year were the most sets released?
SELECT year AS maxYear, COUNT(*)
FROM sets
GROUP BY 1
ORDER BY 2 DESC
LIMIT 1;

#2. Find the id and number of pieces of the inventory with the most parts.
SELECT inventory_id AS id, SUM(quantity) AS total_pieces 
FROM inventory_parts
GROUP BY inventory_id
ORDER BY total_pieces DESC
LIMIT 1;

#3. What is the average color of lego pieces across all inventories?
SELECT CONCAT(HEX(ROUND(SUM(weighted_red)/SUM(quantity),0)), HEX(ROUND(SUM(weighted_green)/SUM(quantity),0)), HEX(ROUND(SUM(weighted_blue)/SUM(quantity),0))) AS avg_color 
FROM (
	SELECT i.quantity AS quantity, c.rgb AS hex, CONV(LEFT(rgb, 2), 16, 10)*quantity AS weighted_red, CONV(SUBSTRING(rgb, 3, 2), 16, 10)*quantity AS weighted_green, CONV(RIGHT(rgb, 2), 16, 10)*quantity AS weighted_blue
	FROM inventory_parts i
	JOIN parts p
	ON p.part_num = i.part_num
	JOIN colors c
	ON color_id = c.id) AS weight_colors;

#Bonus: rarest color
SELECT SUM(i.quantity) AS total_quantity, c.rgb
FROM inventory_parts i
JOIN parts p
ON p.part_num = i.part_num
JOIN colors c
ON color_id = c.id
GROUP BY c.rgb
ORDER BY total_quantity ASC
LIMIT 1;

#4. What is the least common part category across all sets?
SELECT SUM(ip.quantity) AS total_quantity, pc.name
FROM inventory_parts ip
JOIN inventories i ON i.id = ip.inventory_id
JOIN sets s ON i.set_num = s.set_num
JOIN parts p ON ip.part_num = p.part_num
JOIN part_categories pc ON pc.id = p.part_cat_id
GROUP BY pc.name
ORDER BY total_quantity ASC
LIMIT 1;

#5. What are the top three most common parts across all sets, excluding spares?
SELECT SUM(ip.quantity) total_quantity, ip.part_num
FROM inventory_parts ip
JOIN inventories i 
ON ip.inventory_id = i.id
JOIN sets s
ON s.set_num = i.set_num
WHERE ip.is_spare = "f"
GROUP BY ip.part_num
ORDER BY total_quantity DESC
LIMIT 3;

#6.Have the colors of LEGOs included in sets changed over time?
#For this question, I will examine whether there is a statistically significant (greater than 2 standard deviation) change in the average color of a lego piece in a set over decades

CREATE TABLE piece_colors AS SELECT FLOOR(s.year/10)*10 AS decade, ip.quantity AS quantity, c.rgb AS hex, CONV(LEFT(rgb, 2), 16, 10) AS red, CONV(SUBSTRING(rgb, 3, 2), 16, 10) AS green, CONV(RIGHT(rgb, 2), 16, 10) AS blue
FROM sets s 
JOIN inventories i
ON s.set_num = i.set_num
JOIN inventory_parts ip
ON ip.inventory_id = i.id
JOIN parts p
ON p.part_num = ip.part_num
JOIN colors c
ON color_id = c.id;
DELIMITER $$
DROP PROCEDURE IF EXISTS `legoproject`.`test` $$
CREATE PROCEDURE `legoproject`.`test` ()
BEGIN
	DECLARE q INT;
    DECLARE insertions INT;
	SET q = 1;
    WHILE q<1000 DO 
		SET insertions = q - 1;
        DROP TABLE IF EXISTS insert_pieces; 
        CREATE TABLE insert_pieces AS (SELECT * FROM piece_colors WHERE quantity = q);
        WHILE insertions > 0 
        DO
        INSERT INTO piece_colors
		SELECT *
		FROM insert_pieces;
        SET insertions = insertions - 1;
        END WHILE;
        UPDATE piece_colors
		SET quantity = 1
		WHERE quantity = q;
        SET q = q + 1;
    END WHILE;
END $$
DELIMITER ;
CALL test();
ALTER TABLE piece_colors
DROP COLUMN quantity;
SELECT decade, lag_red_mean - red_mean AS change_in_red, red_stddev, CASE WHEN ABS(lag_red_mean-red_mean)>red_stddev THEN 'true' ELSE 'false' END AS red_change_by_stddev,
		lag_green_mean - green_mean AS change_in_green, green_stddev, CASE WHEN ABS(lag_green_mean-green_mean)>green_stddev THEN 'true' ELSE 'false' END AS green_change_by_stddev,
        lag_blue_mean - blue_mean AS change_in_blue, blue_stddev, CASE WHEN ABS(lag_blue_mean-blue_mean)>blue_stddev THEN 'true' ELSE 'false' END AS blue_change_by_stddev
FROM ( 
	SELECT decade, 
		ROUND(SUM(red)/COUNT(*)) AS red_mean, 
		LAG(ROUND(SUM(red)/COUNT(*)), 1, 242) OVER (ORDER BY decade) AS lag_red_mean, 
		ROUND(stddev(red)) AS red_stddev, 
		ROUND(SUM(green)/COUNT(*)) AS green_mean, 
		LAG(ROUND(SUM(green)/COUNT(*)), 1, 211) OVER (ORDER BY decade) AS lag_green_mean,
		ROUND(stddev(green)) AS green_stddev, 
		ROUND(SUM(blue)/COUNT(*)) AS blue_mean, 
		LAG(ROUND(SUM(blue)/COUNT(*)), 1, 208) OVER (ORDER BY decade) AS lag_blue_mean,
		ROUND(stddev(blue)) AS blue_stddev
	FROM piece_colors
	GROUP BY decade
	ORDER BY decade) temp;
#The mean of each color never changes by more than a standard deviation.

#7. How have the size of sets changed over time?
#For this question we are only examining sets with more than 20 pieces because the dataset includes many "sets" that are just piece descriptions 
SELECT release_year, ROUND((avg_parts-lag_avg_parts)*100/lag_avg_parts, 2) AS change_since_last_year, ROUND((avg_parts-24)*100/24, 2) AS change__since_1950
FROM(
	SELECT AVG(num_parts) AS avg_parts, s.year AS release_year, LAG(AVG(num_parts), 1, 24) OVER (ORDER BY s.year) AS lag_avg_parts
	FROM sets s
	WHERE s.num_parts>20
	GROUP By s.year
	ORDER BY s.year) averages;
#LEGO sets tend to grow in average size every year

#8. What decade and theme are most strongly associated?
WITH table1 AS (SELECT COUNT(*) total_sets, t.name AS theme, FLOOR(year/10)*10 AS decade
FROM sets s
JOIN themes t
ON s.theme_id = t.id
GROUP BY theme, decade),
table2 AS (SELECT FLOOR(year/10)*10 AS decade, COUNT(*) AS total_sets
FROM sets s 
JOIN themes t 
ON s.theme_id = t.id
GROUP BY decade
ORDER BY decade)
SELECT t1.theme AS theme, t1.decade, t1.total_sets AS sets_by_theme, t2.total_sets AS total_sets, t1.total_sets/t2.total_sets*100 AS percentage 
FROM table1 t1
JOIN table2 t2 ON t1.decade = t2.decade
WHERE t1.theme != "Supplemental"
ORDER BY percentage DESC;
#Excluding supplemental sets, the 1950's and the Town Plan theme are most strongly associated, with Town Plan making up 26.7% of the 1950's sets 

#9. What is the most common color for each theme?
WITH colors_and_themes AS (
SELECT t.name AS theme, c.rgb AS color, SUM(ip.quantity) AS total_quantity
FROM themes t
JOIN sets s ON s.theme_id = t.id
JOIN inventories i ON i.set_num = s.set_num
JOIN inventory_parts ip ON ip.inventory_id = i.id
JOIN colors c ON ip.color_id = c.id
GROUP BY t.name, c.rgb), 
max_quantities AS (SELECT theme, MAX(total_quantity) AS max_quant FROM colors_and_themes GROUP BY theme)
SELECT ct.theme, color
FROM colors_and_themes ct
JOIN max_quantities mq ON mq.max_quant = ct.total_quantity AND ct.theme = mq.theme;

#10. What is the theme of the set with the median number of parts?
#Again excluding small sets
SELECT *
FROM (SELECT ROW_NUMBER() OVER(ORDER BY num_parts ASC) AS rownum, s.num_parts, t.name
FROM sets s
JOIN themes t 
ON s.theme_id = t.id
WHERE s.num_parts>20)temp
WHERE rownum > 11532/2
LIMIT 1;

SELECT COUNT(*)
FROM sets s;