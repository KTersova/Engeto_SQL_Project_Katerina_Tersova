-- DISCORD: kacka.t, ale poprosím o upřednostnění komunikace přes e-mail (tersova.katerina@email.cz)

-- Před tvorbou finální primární tabulky si pro tento účel vytvořím dvě separátní tabulky pro mzdy a ceny 
-- potravin v jednotlivých letech. Pro účely zodpovězení otázek mohu totiž spoustu informací úplně zanedbat
-- a spíše než ceny potravin v jednotlivých regionech mě budou zajímat průměrné ceny v celé ČR ve zvoleném 
-- časovém období.

-- PRŮMĚRNÉ CENY POTRTAVIN

CREATE OR REPLACE TABLE t_katerina_tersova_prices AS
	SELECT
		year(date_from) AS Rok,
		cpc.name AS Produkt,
		avg(value) AS Cena
	FROM czechia_price AS cp
	JOIN czechia_price_category AS cpc ON cp.category_code = cpc.code 
	WHERE cp.region_code IS NULL
	GROUP BY year(cp.date_from), cpc.name
;

-- Nyní si tuto tabulku pro kontrolu zobrazím

SELECT *
FROM t_katerina_tersova_prices
;

-- A stejným způsobem si vytvořím druhou pomocnou tabulku, v níž budou průměrné platy za jednotlivé roky/odvětví

CREATE OR REPLACE TABLE t_katerina_tersova_wages AS
	SELECT
		cp.payroll_year AS Rok,
		cpi.name AS Název_odvětví,
		cpi.code AS Kód_odvětví,
		AVG(cp.value) AS Průměrná_mzda
	FROM czechia_payroll cp 
	JOIN czechia_payroll_industry_branch cpi ON cp.industry_branch_code = cpi.code 
	WHERE industry_branch_code IS NOT NULL AND value_type_code = 5958 AND calculation_code = 100
	GROUP BY payroll_year, industry_branch_code
;

-- Tabulku si opět zobrazím

SELECT *
FROM t_katerina_tersova_wages
;

-- A nyní spojením těchto dvou pomocných tabulek vytvořím finální 'primary table':

CREATE OR REPLACE TABLE t_katerina_tersova_project_sql_primary_final AS
	SELECT
		tktp.*,
		tktw.Název_odvětví,
		tktw.Kód_odvětví,
		tktw.Průměrná_mzda
	FROM t_katerina_tersova_prices AS tktp
	JOIN t_katerina_tersova_wages AS tktw ON tktp.Rok = tktw.Rok
	JOIN economies eco ON tktp.Rok = eco.year AND eco.country = 'Czech Republic'
	ORDER BY tktp.Rok, tktw.Kód_odvětví
;

-- A opět si tabulku zobrazím:

SELECT *
FROM t_katerina_tersova_project_sql_primary_final
;

-- OTÁZKA 1: Rostou v průběhu let mzdy ve všech odvětvích, nebo v některých klesají?

-- Pro zodpovězení otázky máme k dispozici data z let 2006-2018. Rozhodla jsem se tedy porovnat data na počátku, 
-- vprostředku, a na konci tohoto období (roky 2006, 2012 a 2018).

SELECT 
	t_rok_2006.Název_odvětví,
	ROUND(AVG(t_rok_2006.Průměrná_mzda_2006),2) AS Průměrná_mzda_2006,
	ROUND(AVG(t_rok_2012.Průměrná_mzda_2012),2) AS Průměrná_mzda_2012,
	ROUND(AVG(t_rok_2018.Průměrná_mzda_2018),2) AS Průměrná_mzda_2018,
CASE 
	WHEN AVG(t_rok_2018.Průměrná_mzda_2018)>AVG(t_rok_2012.Průměrná_mzda_2012) THEN '+'
	ELSE '-'
END AS 'Změna mzdy 2012-2018',
CASE 
	WHEN AVG(t_rok_2012.Průměrná_mzda_2012)>AVG(t_rok_2006.Průměrná_mzda_2006) THEN '+'
	ELSE '-'
END AS 'Změna mzdy 2006-2012',
CASE 
	WHEN AVG(t_rok_2018.Průměrná_mzda_2018)>AVG(t_rok_2006.Průměrná_mzda_2006) THEN '+'
	ELSE '-'
END AS 'Změna mzdy 2006-2018'
FROM(
	SELECT DISTINCT 
		Název_odvětví,
		Průměrná_mzda AS Průměrná_mzda_2006,
		Rok
	FROM t_katerina_tersova_project_sql_primary_final
	WHERE Rok = '2006') AS t_rok_2006
JOIN( 
	SELECT DISTINCT 
		Název_odvětví,
		Průměrná_mzda AS Průměrná_mzda_2012,
		Rok
	FROM t_katerina_tersova_project_sql_primary_final
	WHERE Rok = '2012') AS t_rok_2012
ON t_rok_2006.Název_odvětví = t_rok_2012.Název_odvětví
JOIN( 
	SELECT DISTINCT 
		Název_odvětví,
		Průměrná_mzda AS Průměrná_mzda_2018,
		Rok
	FROM t_katerina_tersova_project_sql_primary_final
	WHERE Rok = '2018') AS t_rok_2018
ON t_rok_2012.Název_odvětví = t_rok_2018.Název_odvětví
GROUP BY 
	t_rok_2006.Rok,
	t_rok_2006.Název_odvětví;
;

-- ODPOVĚĎ: Jak vidíme, změna ve všech odvětvích ve odvětvích sledovaných časových úsecích je kladná, tedy mzdy vždy rostly. 

-- OTÁZKA 2: Kolik je možné si koupit litrů mléka a koupit chleba za první a koupit srovnatelné období v dostupných 
-- datech cen a mezd?

SELECT Produkt,
	   Rok,
	   ROUND(AVG(Průměrná_mzda), 2) AS Průměrná_mzda,
	   ROUND(AVG(Cena),2) AS Cena,
       ROUND(AVG(Průměrná_mzda)/AVG(Cena),0) AS Zakoupitelné_množství
FROM t_katerina_tersova_project_sql_primary_final
WHERE Produkt IN ('Chléb konzumní kmínový','Mléko polotučné pasterované') 
	  AND Rok IN ('2006','2018')
GROUP BY 
	Produkt,
	Rok
;

-- Vidíme, že zakoupitelné množství se v případě obou sledovaných produktů zvýšílo. V případě kmínového chleba o 57 
-- bochníků, u mléka potom o 205 litrů.

-- OTÁZKA 3: Která kategorie potravin zdražuje nejpomaleji (je u ní nejnižší percentuální meziroční nárůst)?

-- Nejprve si ověříme, že záznam pro každou kategorii potravin mám ve všech sledovaných obdobích:

SELECT 
	Produkt, 
	COUNT(Rok) AS 'Počet záznamů'
FROM t_katerina_tersova_project_sql_primary_final
GROUP BY Produkt
;

-- Vidíme tedy, že pro jakostní víno bílé nemáme všechny záznamy. Bude tedy lepší tento produkt z analýzy vyjmout.

CREATE OR REPLACE TABLE t_katerina_tersova_rocni_zmeny_cen AS 
SELECT 
	DISTINCT(tktf.Produkt),
	tktf.Rok,
	ROUND(tktf.Cena,2) AS Cena,
	ROUND(tktf2.Cena,2) AS Cena_v_předchozím_roce,
	ROUND(((tktf.Cena / tktf2.Cena) * 100)-100, 1) AS Roční_procentuální_změna
FROM t_katerina_tersova_project_sql_primary_final AS tktf 
JOIN t_katerina_tersova_project_sql_primary_final AS tktf2 ON tktf.Rok = tktf2.Rok + 1
WHERE tktf.Produkt = tktf2.Produkt
HAVING tktf.Produkt NOT LIKE 'Jakostní víno bílé'
ORDER BY tktf.Rok
;

 SELECT *
 FROM t_katerina_tersova_rocni_zmeny_cen
;

-- A nyní si zobrazím průměrnou procentuální změnu ceny jednotlivých prodktů za celé období:

SELECT 
	Produkt,
	MAX(Roční_procentuální_změna) + ABS(MIN(Roční_procentuální_změna)) AS Maximální_rozdíl_procenta,
	ROUND(AVG(Roční_procentuální_změna), 2) AS Průměrná_roční_změna_procenta
FROM t_katerina_tersova_rocni_zmeny_cen
GROUP BY Produkt
ORDER BY AVG(Roční_procentuální_změna)
;

-- ODPOVĚĎ: Otázka zní který produkt zdražuje nejpomaleji. Dalo by se tedy říct, že hledám nejnižší kladnou hodnotu 
-- průměné roční změny, což jsou Banány žluté (0.83%). Jsou nicméně dvě kategorie potravin - Cukr krystalový a Rajská 
-- jablka červená, které v průměru dokonce zlevňují. Cukr o 1,92%, Jablka o 0,75%.

-- OTÁZKA 4: Existuje rok, ve kterém byl meziroční nárůst cen potravin výrazně vyšší než růst mezd (větší než 10 %)?

-- Nejrpve si vytvořím pomocnou tabulku pro meziroční rozdíly ve výši mezd: 

CREATE OR REPLACE TABLE t_katerina_tersova_rocni_zmeny_mezd AS
SELECT
	Rok,
	Název_odvětví,
	Průměrná_mzda,
	LAG(Průměrná_mzda)
		OVER (PARTITION BY Kód_odvětví ORDER BY Rok) AS Mzda_v_předchozím_roce,
	ROUND((Průměrná_mzda / LAG(Průměrná_mzda)
		OVER (PARTITION BY Kód_odvětví ORDER BY Rok) * 100)-100, 1) AS Roční_procentuální_změna
FROM t_katerina_tersova_project_sql_primary_final AS tktf
GROUP BY Rok, Kód_odvětví
ORDER BY Rok, Název_odvětví
;

SELECT *
FROM t_katerina_tersova_rocni_zmeny_mezd
;

-- A nyní si do jedné tabulky zobrazím meziroční průměrnou změnu v cenách produktů 
-- (průměr v jednotlivých letech pro všechny produkty dohromady) a průměrnou meziroční změnu ve mzdách, opět pro 
-- všechna odvětví zprůměrujeme do jednoho čísla. Tyto dvě hodnoty od sebe následně odečtu.

SELECT 
	ceny.Rok, 
	ROUND(AVG(ceny.Roční_procentuální_změna), 2) AS Průměr_cen, 
	ROUND(AVG(mzdy.Roční_procentuální_změna), 2) AS Průměr_mezd,
	ROUND(AVG(ceny.Roční_procentuální_změna) - AVG(mzdy.Roční_procentuální_změna), 2) AS Rozdíl_mezd_a_cen
FROM t_katerina_tersova_rocni_zmeny_mezd AS mzdy
JOIN t_katerina_tersova_rocni_zmeny_cen AS ceny 
	ON mzdy.Rok = ceny.Rok 
GROUP BY ceny.Rok
ORDER BY Rozdíl_mezd_a_cen DESC
;

-- Vidím, že rozdíl větší než 10% nenastal v žádném roce. Nejblíže tomu byl rok 2013, kdy ceny potravin rostly 
-- o 6.78% rychleji, než mzdy. 
-- ODPOVĚĎ: Ne, neextuje rok, ve kterém by meziroční nárůst cen potravin byl o více než 10% vyšší, než růst mezd.

-- OTÁZKA 5: Má výška HDP vliv na změny ve mzdách a cenách potravin? Neboli, pokud HDP vzroste výrazněji v jednom 
-- roce, projeví se to na cenách potravin či mzdách ve stejném nebo násdujícím roce výraznějším růstem?

-- Začnu vytvořením sekundární tabulky:

CREATE OR REPLACE TABLE t_katerina_tersova_project_sql_secondary_final  AS
	SELECT 
		e.`year` AS Rok,	
		e.country AS Země,
		e.GDP AS HDP,
		e.population AS Počet_obyvatel,
		e.gini AS Giniho_koeficient
	FROM economies AS e
	JOIN countries AS c 
		ON e.country = c.country 
	WHERE gini IS NOT NULL AND 
		c.continent LIKE 'Europe'
	ORDER BY e.country, e.`year`
;

SELECT *
FROM t_katerina_tersova_project_sql_secondary_final 
;

-- Následně si tedy do jedné tabulky dám meziroční procentuální rozdíl jak pro HDP, tak pro mzdy a ceny potravin. 
-- Českou republiku filtruji proto, že pro ostatní státy nemáme k dispozici data o mzdách a cenách potravin. Bude 
-- tedy nejlepší zaměřit se právě na Českou Republiku. 

SELECT
    hdp.Rok,
    hdp.Země,
--  hdp.HDP, 
--  LAG(hdp.HDP) OVER (PARTITION BY hdp.Země ORDER BY hdp.Rok) AS Predchozi_rok_HDP,
-- Tyto dva řádky použít, pokud bychom chtěli vidět i data pro HDP a HDP v předcházejícím roce, z nichž je vypočten procentuální meziroční rozdíl. Pro účely
-- zodpovězení výzkumné otázky to však není nutné
    ROUND((hdp.HDP - LAG(hdp.HDP) 
    	OVER (PARTITION BY hdp.Země ORDER BY hdp.Rok)) / LAG(hdp.HDP) 
    	OVER (PARTITION BY hdp.Země ORDER BY hdp.Rok) * 100, 2) 
    		AS Mezirocni_rozdil_HDP,
    mzdy.Roční_procentuální_změna AS Meziroční_procentuální_změna_mezd,
    ROUND(AVG(ceny.Roční_procentuální_změna), 2) AS Meziroční_procentuální_změna_cen
FROM t_katerina_tersova_project_sql_secondary_final AS hdp
JOIN t_katerina_tersova_rocni_zmeny_mezd mzdy 
    ON hdp.Rok = mzdy.Rok
JOIN t_katerina_tersova_rocni_zmeny_cen ceny 
    ON hdp.Rok = ceny.Rok
WHERE hdp.Země = 'Czech Republic'
GROUP BY 
    hdp.Rok, 
    hdp.Země, 
    hdp.HDP
ORDER BY hdp.Rok
;
    
-- ODPOVĚĎ: Jak vidíme, meziroční změny HDP se v nadcházejícím roce vždy projevily na růstu mezd. V případě propadu 
-- HDP v následujícím roce mzdy rostly oproti předcházejícím letům pomaleji. Naopak v případě rychle rostoucího HDP 
-- (například v roce 2015) můžeme v následujícím roce pozorovat veliký nárůst mezd, a to o 5.9%. 
-- Naproti tomu vztah mezi HDP a cenami potravin již tak zřejmý není. V některých letech by se mohlo zdát, že rostoucí
-- HDP má za důsledek zlevňování (roky 2014 až 2016), nicméně toto nám vyvrací hned rok 2017, kdy je nárůst HDP sice 
-- značný, ale ceny vyrostly o více než 7%. Zde bych tedy žádnou vazbu na základě těchto dat nehledala.
