USE [FoodDB]

UPDATE fooFoodRecipe SET Netto = 0 WHERE Netto IS NULL

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[f_fooMeasureUnitStr](@MenuId int, @DocumentTypeID int) 
RETURNS TABLE  AS
RETURN (

SELECT FoodID, ' ('+MAX([1]) + ISNULL(', '+MAX([2]),'') + ISNULL(', '+MAX([3]),'')+ ISNULL(', '+MAX([4]),'')+ ISNULL(', '+MAX([5]),'') +')' as MeasureUnitString
FROM 
	(
	select FoodID, max(isnull(fooIncDocDetail.IsUndividedPack,0)) AS UP,
		ROW_NUMBER() over (partition by FoodID order by MeasureUnit) AS RN,
		case when sum(fooExpDocDetail.Amount) <> 0 then [dbo].[BeautyStr](sum(fooExpDocDetail.Amount))+ ' по '+ ltrim(Str(MeasureUnit,7,3)) else '' end AS StrAMU
	from fooDocument 
		inner join fooExpDocDetail on fooDocument.DocumentID = fooExpDocDetail.DocumentID
		inner join fooIncDocDetail on fooExpDocDetail.IncDocDetailID = fooIncDocDetail.IncDocDetailID
		inner join fooMenu on fooDocument.DocDate = fooMenu.MenuDate and fooDocument.ObjectID = fooMenu.ObjectID and fooMenu.MenuId = @MenuId
	where fooDocument.DocumentTypeID = @DocumentTypeID and fooDocument.RecordStatusID=1 and fooExpDocDetail.RecordStatusID=1 and fooIncDocDetail.RecordStatusID=1 
		and fooExpDocDetail.Amount <> 0 
	group by FoodID, MeasureUnit
	) p
	PIVOT
	(
		min(StrAMU)
		FOR RN IN ([1],[2],[3],[4],[5])
	) as p

	GROUP BY FoodID
	HAVING MAX(UP)>0
)

GO

CREATE FUNCTION [dbo].[f_fooMenuFullJoinDetail](@MenuId int) 

/*Функция возвращает список всех продуктов (списание и довложение), потраченных в связи с данным MenuID*/

RETURNS TABLE AS

RETURN (
		SELECT ISNULL(DocDetail.FoodID, DocDetailDop.FoodID) AS FoodID, ISNULL(DocDetail.Name, DocDetailDop.Name) AS Name, ISNULL(DocDetail.NomenclatureID
				, DocDetailDop.NomenclatureID) AS NomenclatureID, ISNULL(DocDetail.Price, DocDetailDop.Price) AS Price, ISNULL(DocDetail.Amount, 
				DocDetailDop.Amount) AS Amount, ISNULL(DocDetail.FoodPercent, DocDetailDop.FoodPercent) AS FoodPercent, ISNULL(DocDetail.LossPercent, 
				DocDetailDop.LossPercent) AS LossPercent, ISNULL(DocDetail.EggMeasureUnit, DocDetailDop.EggMeasureUnit) AS EggMeasureUnit, ISNULL(
				DocDetail.MeasureUnitString, ISNULL(DocDetailDop.MeasureUnitString, '')) AS MeasureUnitString, ISNULL(DocDetail.Food1C, DocDetailDop.
				Food1C) AS Food1C, ISNULL(DocDetail.IsMain, DocDetailDop.IsMain) AS IsMain, DocDetail.Price AS DocDetailPrice, DocDetailDop.Price AS 
			DocDetailDopPrice, DocDetail.EggMeasureUnit AS DocDetailEggMeasureUnit, DocDetailDop.EggMeasureUnit AS DocDetailDopEggMeasureUnit, DocDetail
			.FoodID AS DocDetailFoodID, DocDetailDop.FoodID AS DocDetailDopFoodID, DocDetail.FoodPercent AS DocDetailFoodPercent, DocDetailDop.FoodPercent 
			AS DocDetailDopFoodPercent, DocDetailDop.LossPercent AS DocDetailDopLossPercent, DocDetail.LossPercent AS DocDetailLossPercent, DocDetail.
			Amount AS DocDetailAmount, DocDetailDop.Amount AS DocDetailDopAmount
		FROM (
			SELECT fooIncDocDetail.FoodID, foofood.Name, foofood.NomenclatureID, SUM(fooIncDocDetail.Price * (1 + ISNULL(fooIncDocDetail.VATRate / 100, 0)
						) * fooExpDocDetail.Amount) / SUM(fooExpDocDetail.Amount * IIF(fooIncDocDetail.FoodID = 189, 1, fooIncDocDetail.MeasureUnit)) AS 
				Price, SUM(fooExpDocDetail.Amount * fooIncDocDetail.MeasureUnit * fooUnitMeasureKoef.Koef) AS Amount, SUM(fooExpDocDetail.Amount * 
					fooIncDocDetail.MeasureUnit) / SUM(SUM(fooExpDocDetail.Amount * fooIncDocDetail.MeasureUnit)) OVER (PARTITION BY fooFood.NomenclatureID
					) AS FoodPercent /*процент расхода продукта в рамках расхода по номенклатуре*/, CASE 
					WHEN fooIncDocDetail.FoodID IN (192, 66, 308)
						THEN CASE fooIncDocDetail.LossPercent
								WHEN 0
									THEN fooFoodLoss.PercentValue
								ELSE fooIncDocDetail.LossPercent
								END
					ELSE fooIncDocDetail.LossPercent
					END AS LossPercent, IIF(fooIncDocDetail.FoodID = 189, SUM(fooIncDocDetail.MeasureUnit * fooExpDocDetail.Amount) / SUM(fooExpDocDetail.
						Amount), 1) AS EggMeasureUnit, MU.MeasureUnitString, foofood.Code1C AS Food1C, fooObjectPerson.IsMain
			FROM fooDocument
			INNER JOIN fooExpDocDetail ON fooDocument.DocumentID = fooExpDocDetail.DocumentID
			INNER JOIN fooIncDocDetail ON fooExpDocDetail.IncDocDetailID = fooIncDocDetail.IncDocDetailID
			INNER JOIN fooDocument IncDocument ON fooIncDocDetail.DocumentID = IncDocument.DocumentID
			INNER JOIN fooObjectPerson ON IncDocument.ObjectPersonID = fooObjectPerson.ObjectPersonID
			INNER JOIN fooMenu ON fooDocument.DocDate = fooMenu.MenuDate
				AND fooDocument.ObjectID = fooMenu.ObjectID
				AND fooMenu.MenuId = @MenuId
			INNER JOIN fooFood ON fooFood.FoodID = fooIncDocDetail.FoodID
			LEFT JOIN fooFoodLoss ON fooFood.FoodID = fooFoodLoss.FoodID
				AND ISNULL(fooFoodLoss.MonthID, Month(MenuDate)) = Month(MenuDate)
			INNER JOIN fooUnitMeasureKoef ON fooIncDocDetail.UnitMeasureID = fooUnitMeasureKoef.UnitMeasureIDInc
				AND fooFood.UnitMeasureID = fooUnitMeasureKoef.UnitMeasureIDMenu
			LEFT JOIN [dbo].[f_fooMeasureUnitStr](@MenuId, 3 /*тип документа*/) AS MU ON fooIncDocDetail.FoodID = MU.FoodID
			WHERE fooDocument.DocumentTypeID = 3 AND fooDocument.RecordStatusID = 1
				AND fooExpDocDetail.RecordStatusID = 1 AND fooIncDocDetail.RecordStatusID = 1
				AND fooExpDocDetail.Amount <> 0
			GROUP BY fooIncDocDetail.FoodID, fooFood.Name, foofood.NomenclatureID, CASE 
					WHEN fooIncDocDetail.FoodID IN (192, 66, 308)
						THEN CASE fooIncDocDetail.LossPercent
								WHEN 0
									THEN fooFoodLoss.PercentValue
								ELSE fooIncDocDetail.LossPercent
								END
					ELSE fooIncDocDetail.LossPercent
					END, fooFood.Code1c, fooObjectPerson.IsMain, MU.MeasureUnitString
			) AS DocDetail
		FULL JOIN (
			SELECT fooIncDocDetail.FoodID, foofood.Name, foofood.NomenclatureID, SUM(fooIncDocDetail.Price * (1 + ISNULL(fooIncDocDetail.VATRate / 100, 0)
						) * fooExpDocDetail.Amount) / SUM(fooExpDocDetail.Amount * IIF(fooIncDocDetail.FoodID = 189, 1, fooIncDocDetail.MeasureUnit)) AS 
				Price, SUM(fooExpDocDetail.Amount * fooIncDocDetail.MeasureUnit * fooUnitMeasureKoef.Koef) AS Amount, SUM(fooExpDocDetail.Amount * 
					fooIncDocDetail.MeasureUnit) / SUM(SUM(fooExpDocDetail.Amount * fooIncDocDetail.MeasureUnit)) OVER (PARTITION BY fooIncDocDetail.FoodID
					) AS FoodPercent, CASE 
					WHEN fooIncDocDetail.FoodID IN (192, 66, 308)
						THEN CASE fooIncDocDetail.LossPercent
								WHEN 0
									THEN fooFoodLoss.PercentValue
								ELSE fooIncDocDetail.LossPercent
								END
					ELSE fooIncDocDetail.LossPercent
					END AS LossPercent, 
					IIF(fooIncDocDetail.FoodID=189, SUM(fooIncDocDetail.MeasureUnit*fooExpDocDetail.Amount)/SUM(fooExpDocDetail.Amount), 1) AS EggMeasureUnit, 
					MU.MeasureUnitString, foofood.Code1C AS Food1C, fooObjectPerson.IsMain
			FROM fooDocument
			INNER JOIN fooExpDocDetail ON fooDocument.DocumentID = fooExpDocDetail.DocumentID
			INNER JOIN fooIncDocDetail ON fooExpDocDetail.IncDocDetailID = fooIncDocDetail.IncDocDetailID
			INNER JOIN fooDocument IncDocument ON fooIncDocDetail.DocumentID = IncDocument.DocumentID
			INNER JOIN fooObjectPerson ON IncDocument.ObjectPersonID = fooObjectPerson.ObjectPersonID
			INNER JOIN fooMenu ON fooDocument.DocDate = fooMenu.MenuDate
				AND fooDocument.ObjectID = fooMenu.ObjectID
				AND fooMenu.MenuId = @MenuId
			INNER JOIN foofood ON foofood.FoodID = fooIncDocDetail.FoodID
			LEFT JOIN fooFoodLoss ON fooFood.FoodID = fooFoodLoss.FoodID
				AND ISNULL(fooFoodLoss.MonthID, Month(MenuDate)) = Month(MenuDate)
			INNER JOIN fooUnitMeasure AS fooUnitMeasureInc ON fooIncDocDetail.UnitMeasureID = fooUnitMeasureInc.UnitMeasureID
			INNER JOIN fooUnitMeasure AS fooUnitMeasureFood ON foofood.UnitMeasureID = fooUnitMeasureFood.UnitMeasureID
			INNER JOIN fooUnitMeasureKoef ON fooUnitMeasureInc.UnitMeasureID = fooUnitMeasureKoef.UnitMeasureIDInc
				AND fooUnitMeasureFood.UnitMeasureID = fooUnitMeasureKoef.UnitMeasureIDMenu
			LEFT JOIN [dbo].[f_fooMeasureUnitStr](@MenuId, 7 /*тип документа*/) AS MU ON fooIncDocDetail.FoodID = MU.FoodID
			WHERE fooDocument.DocumentTypeID = 7
				AND fooDocument.RecordStatusID = 1
				AND fooExpDocDetail.RecordStatusID = 1
				AND fooIncDocDetail.RecordStatusID = 1
				AND fooExpDocDetail.Amount <> 0
			GROUP BY fooIncDocDetail.FoodID, foofood.NomenclatureID, foofood.Name, CASE 
					WHEN fooIncDocDetail.FoodID IN (192, 66, 308)
						THEN CASE fooIncDocDetail.LossPercent
								WHEN 0
									THEN fooFoodLoss.PercentValue
								ELSE fooIncDocDetail.LossPercent
								END
					ELSE fooIncDocDetail.LossPercent
					END, fooFood.Code1c, fooObjectPerson.IsMain, MU.MeasureUnitString
			) AS DocDetailDop ON DocDetail.FoodID = DocDetailDop.FoodID AND DocDetail.LossPercent = DocDetailDop.LossPercent
		)
GO


ALTER FUNCTION [dbo].[f_fooMenuByExpDocumentVersion] (@MenuId INT)
RETURNS @MenuByExpDocument TABLE (
	FoodID INT, Name VARCHAR(100), NomenclatureID INT, UnitMeasure VARCHAR(50), EatingTime VARCHAR(50), EatingTimeID INT, MenuId INT, MenuDate DATETIME, ObjectID 
	INT, [Object] VARCHAR(50), UltraShortName VARCHAR(50), EatingCategoryID INT, EatingCategory VARCHAR(50), PortionCount INT, PortionCountFact INT, 
	ControlPortionCount INT, Recipe VARCHAR(100), OriginalRecipe VARCHAR(100), RecipeID INT, Netto DECIMAL(18, 5), BruttoByRecalcPlan DECIMAL(18, 5), 
	BruttoByRecalcDop DECIMAL(18, 5), FoodPercent DECIMAL(18, 5), LossPercent DECIMAL(18, 5), BruttoByRecalcFact DECIMAL(18, 5), Brutto DECIMAL(18, 5), FoodLoss 
	DECIMAL(18, 5), Price DECIMAL(18, 5), PersonPortionCount INT, NettoRecipe DECIMAL(18, 5), PortionCount24 INT, ParentMenuCategoryTimeRecipeID INT, 
	MenuCategoryTimeRecipeID INT, IsHeat INT, OrderNumber INT, MenuCorrectionTypeID INT, IsVisible INT, DocFoodID INT, EggMeasureUnit DECIMAL(18, 5), MenuAmount 
	DECIMAL(18, 5), MenuAmountEatingCategory DECIMAL(18, 5), MenuAmountDopEatingCategory DECIMAL(18, 5), ExpAmount DECIMAL(18, 5), ExpAmountDop DECIMAL(18, 5)
	, mainEatingCategoryID INT, mainEatingCategoryDopID INT, DocLossPercent DECIMAL(18, 5), RecipeLoss DECIMAL(18, 5), KoefToNorm DECIMAL(18, 5), 
	OrderNumberEatingCategory INT, OrderNumberEatingTime INT, MeasureUnitString VARCHAR(100), BoilLoss DECIMAL(18, 5), IsAlone INT, OrderForExp INT, Food1C 
	VARCHAR(50), EatingCategory1C VARCHAR(50), RoundTo DECIMAL(3, 1), PersonAmount DECIMAL(18, 5), IsMain INT
	)
AS
BEGIN
	IF (SELECT ObjectID FROM fooMenu WHERE MenuId = @MenuId ) IN (232, 93) /*МБДОУ №93 к3, МБДОУ13*/
		INSERT INTO @MenuByExpDocument
		SELECT FoodID, t.Name, NomenclatureID, UnitMeasure, EatingTime, EatingTimeID, MenuId, MenuDate, ObjectID, [Object], UltraShortName, t.
			EatingCategoryID, t.EatingCategory, PortionCount, PortionCountFact, ControlPortionCount, Recipe, OriginalRecipe, RecipeID, Netto, 
			BruttoByRecalcPlan, BruttoByRecalcDop, FoodPercent, LossPercent, BruttoByRecalcFact, Brutto, FoodLoss, Price, PersonPortionCount, NettoRecipe, 
			PortionCount24, ParentMenuCategoryTimeRecipeID, MenuCategoryTimeRecipeID, IsHeat, OrderNumber, MenuCorrectionTypeID, IsVisible, DocFoodID, 
			EggMeasureUnit, 
			ROUND(SUM(ROUND(BruttoByRecalcPlan * PortionCount, 3)) OVER (
					PARTITION BY FoodID, LossPercent, EatingCategory ORDER BY t.OrderForExp
					) / EggMeasureUnit, 3) AS MenuAmount, 
			ROUND(SUM(ROUND(BruttoByRecalcPlan * PortionCount, 3)) OVER (
					PARTITION BY FoodID, LossPercent, EatingCategory ORDER BY t.OrderForExp
					) / EggMeasureUnit, 3) AS MenuAmountEatingCategory, 
			ROUND(SUM(ROUND(BruttoByRecalcDop * (PortionCountFact - PortionCount), 3)) OVER (
					PARTITION BY FoodID, LossPercent, EatingCategory ORDER BY t.OrderForExp
					) / EggMeasureUnit, 3) AS MenuAmountDopEatingCategory, 
			ExpAmount, ExpAmountDop, 
			SUM(MainEatingCategory) OVER (PARTITION BY FoodID) AS mainEatingCategoryID, 
			SUM(MainEatingCategoryDop) OVER (PARTITION BY FoodID) AS mainEatingCategoryDopID, 
			DocLossPercent, RecipeLoss, KoefToNorm, OrderNumberEatingCategory, OrderNumberEatingCategory AS OrderNumberEatingTime, ISNULL(MeasureUnitString,'') AS MeasureUnitString, 
			BoilLoss, 
			CASE 
				WHEN COUNT(FoodID) OVER (PARTITION BY MenuCategoryTimeRecipeID) = 1
					THEN 1
				ELSE 0
				END AS IsAlone, OrderForExp, t.Food1C, t.EatingCategory1C, RoundTo, 
				ROUND(SUM(ROUND(BruttoByRecalcPlan * PersonPortionCount, 3)) OVER (PARTITION BY MenuId, FoodID, LossPercent, EatingCategory ORDER BY t.OrderForExp
					) / EggMeasureUnit, 3) AS PersonAmount, IsMain
		FROM (
			SELECT Detail.FoodID, Detail.Name, v_fooMenu.NomenclatureID, v_fooMenu.UnitMeasure, v_fooMenu.EatingTime, v_fooMenu.EatingTimeID, v_fooMenu.
				MenuId, v_fooMenu.MenuDate, v_fooMenu.ObjectID, v_fooMenu.[Object], v_fooMenu.UltraShortName, v_fooMenu.EatingCategoryID, v_fooMenu.
				EatingCategory, v_fooMenu.PortionCount, v_fooMenu.PortionCountFact, v_fooMenu.ControlPortionCount, v_fooMenu.Recipe, v_fooMenu.
				OriginalRecipe, v_fooMenu.RecipeID, v_fooMenu.Netto, RecipeLossOriginal AS RecipeLoss, BoilLoss, PortionCount24, AllPortionCount, CASE 
					WHEN ROW_NUMBER() OVER (
							PARTITION BY DocDetailFoodID, ISNULL(SkyRecipeLoss, 1) * DocDetailLossPercent, DocDetailFoodPercent ORDER BY 
								BruttoSkyFood / (1 - DocDetailLossPercent / 100.00) * AllPortionCount DESC, OrderForExp 
								DESC, OrderNumber DESC, RecipeID, DocDetailFoodPercent DESC, MenuCategoryTimeRecipeID
							) = 1
						THEN (
								ISNULL(DocDetailAmount, 0) - SUM(DocDetailFoodPercent * BruttoSkyFood / (1 - DocDetailLossPercent / 100.00
										) * AllPortionCount) OVER (PARTITION BY DocDetailFoodID, v_fooMenu.MenuId, ISNULL(SkyRecipeLoss, 1) * DocDetailLossPercent, DocDetailFoodPercent
									)
								) / AllPortionCount + BruttoSkyFood / (1 - DocDetailLossPercent / 100.00) * 
							DocDetailFoodPercent
					ELSE BruttoSkyFood / (1 - DocDetailLossPercent / 100.00) * DocDetailFoodPercent
					END AS BruttoByRecalcPlan, Detail.FoodPercent, ISNULL(SkyRecipeLoss, 1) * Detail.LossPercent AS LossPercent, Detail.LossPercent AS 
				DocLossPercent, 0 AS BruttoByRecalcFact, CASE 
					WHEN DocDetailDopFoodID = Detail.FoodID
						THEN CASE 
								WHEN MenuCorrectionTypeID = 1
									AND (AllPortionCountFact - AllPortionCount) <> 0
									THEN CASE 
											WHEN OrderForExp = max(OrderForExp) OVER (PARTITION BY v_fooMenu.FoodID, v_fooMenu.MenuId, DocDetailDopFoodPercent
													)
												AND ROW_NUMBER() OVER (
														PARTITION BY v_fooMenu.FoodID, OrderForExp, ISNULL(SkyRecipeLoss, 1) * 
															DocDetailDopLossPercent, DocDetailDopFoodPercent, MenuCorrectionTypeID 
														ORDER BY BruttoSkyFood/(1 - DocDetailDopLossPercent / 100.00), OrderNumber DESC, RecipeID) 
													= COUNT(1) OVER (
														PARTITION BY v_fooMenu.FoodID, OrderForExp, ISNULL(SkyRecipeLoss, 1) * 
															DocDetailDopLossPercent, DocDetailDopFoodPercent, MenuCorrectionTypeID)
												THEN (ISNULL(DocDetailDopAmount, 0) - SUM(DocDetailDopFoodPercent * BruttoSkyFood / (1 - DocDetailDopLossPercent / 100.00
																) * (AllPortionCountFact - AllPortionCount
																)) OVER (
															PARTITION BY v_fooMenu.FoodID, ISNULL(SkyRecipeLoss, 1) * 
																DocDetailDopLossPercent, DocDetailDopFoodPercent, MenuCorrectionTypeID 
															ORDER BY OrderForExp, BruttoSkyFood / (1 - DocDetailDopLossPercent / 100.00), OrderNumber DESC, RecipeID
															)
														) / (AllPortionCountFact - AllPortionCount
														) + BruttoSkyFood*DocDetailDopFoodPercent/(1 - DocDetailDopLossPercent / 100.00) 
											ELSE BruttoSkyFood*DocDetailDopFoodPercent/(1 - DocDetailDopLossPercent/100.00)
											END
								ELSE 0
								END
					ELSE 0
					END AS BruttoByRecalcDop, OrderNumberEatingCategory, v_fooMenu.Brutto, v_fooMenu.FoodLoss, Detail.Price AS Price, KoefToNorm, 
				MenuNumber, SignDate, v_fooMenu.PersonPortionCount, v_fooMenu.NettoRecipe, v_fooMenu.ParentMenuCategoryTimeRecipeID, v_fooMenu.
				MenuCategoryTimeRecipeID, v_fooMenu.IsHeat, v_fooMenu.OrderNumber, v_fooMenu.MenuCorrectionTypeID, IsVisible, Detail.FoodID AS DocFoodID, Detail.EggMeasureUnit, 
				IIF(DocDetailFoodID=189, ROUND(ISNULL(DocDetailAmount, 0)/DocDetailEggMeasureUnit, 0),ISNULL(DocDetailAmount, 0)/DocDetailEggMeasureUnit) AS ExpAmount, 
				CASE 
					WHEN DocDetailDopFoodID = Detail.FoodID
						THEN IIF(DocDetailDopFoodID=189, ROUND(ISNULL(DocDetailDopAmount, 0)/DocDetailDopEggMeasureUnit, 0)
									,ISNULL(DocDetailDopAmount, 0)/DocDetailDopEggMeasureUnit)
					ELSE 0
					END AS ExpAmountDop, v_fooMenu.RoundTo, OrderForExp, 
				CASE 
					WHEN ROW_NUMBER() OVER (PARTITION BY Detail.FoodID ORDER BY BruttoSkyFood * PortionCount DESC) = 1
						THEN EatingCategoryID
					ELSE 0
					END AS MainEatingCategory, 
				CASE 
					WHEN MenuCorrectionTypeID = 1
						THEN CASE 
								WHEN ROW_NUMBER() OVER (PARTITION BY v_fooMenu.FoodID, MenuCorrectionTypeID ORDER BY BruttoSkyFood * PortionCount DESC) = 1
									THEN EatingCategoryID
								ELSE 0
								END
					ELSE 0
					END AS MainEatingCategoryDop, Detail.MeasureUnitString, Detail.Food1C, EatingCategory1C, Detail.IsMain
			FROM v_fooMenu
			LEFT JOIN [dbo].[f_fooMenuFullJoinDetail](@MenuId) AS Detail
				ON Detail.NomenclatureID = v_fooMenu.NomenclatureID
			WHERE NettoRecipe <> 0
				AND (PortionCount + PersonPortionCount) <> 0
				AND v_fooMenu.IsFromStorage = 1
				AND v_fooMenu.MenuId = @MenuId
				AND v_fooMenu.EatingCategoryID NOT IN (12, 13)
			) AS t
	ELSE
		INSERT INTO @MenuByExpDocument

		SELECT t.FoodID, t.Name, NomenclatureID, UnitMeasure, EatingTime, EatingTimeID, MenuId, MenuDate, ObjectID, [Object], UltraShortName, t.
			EatingCategoryID, t.EatingCategory, PortionCount, PortionCountFact, ControlPortionCount, Recipe, OriginalRecipe, RecipeID, Netto, 
			BruttoByRecalcPlan, BruttoByRecalcDop, FoodPercent, LossPercent, BruttoByRecalcFact, Brutto, FoodLoss, Price, PersonPortionCount, NettoRecipe, 
			PortionCount24, ParentMenuCategoryTimeRecipeID, MenuCategoryTimeRecipeID, IsHeat, OrderNumber, MenuCorrectionTypeID, IsVisible, DocFoodID, 
			EggMeasureUnit, 
			ROUND(SUM(ROUND(BruttoByRecalcPlan * (PortionCount + ControlPortionCount + PortionCount24), 3)) 
				OVER (PARTITION BY FoodID, LossPercent, EatingCategory 
						ORDER BY t.OrderForExp) / EggMeasureUnit, 3) AS MenuAmount, 
			ROUND(SUM(ROUND(BruttoByRecalcPlan * PortionCount, 3)) 
				OVER (
					PARTITION BY FoodID, LossPercent, EatingCategory ORDER BY t.OrderForExp
					) / EggMeasureUnit, 3) AS MenuAmountEatingCategory, 
			ROUND(SUM(ROUND(BruttoByRecalcDop * (PortionCountFact - PortionCount
							), 3)) OVER (
					PARTITION BY FoodID, LossPercent, EatingCategory ORDER BY t.OrderForExp
					) / EggMeasureUnit, 3) AS MenuAmountDopEatingCategory, ExpAmount, ExpAmountDop, fooEatingCategory.EatingCategoryID AS 
			mainEatingCategoryID, fooEatingCategoryDop.EatingCategoryID AS mainEatingCategoryDopID, DocLossPercent, RecipeLoss, KoefToNorm, 
			OrderNumberEatingCategory, OrderNumberEatingCategory AS OrderNumberEatingTime, ISNULL(MeasureUnitString,'') AS MeasureUnitString, BoilLoss AS BoilLoss, 
			CASE 
				WHEN COUNT(FoodID) OVER (PARTITION BY MenuCategoryTimeRecipeID) = 1
					THEN 1
				ELSE 0
				END AS IsAlone, t.OrderForExp, t.Food1C, t.EatingCategory1C, RoundTo, ROUND(SUM(ROUND(BruttoByRecalcPlan * PersonPortionCount, 3)) OVER (
					PARTITION BY FoodID, LossPercent, EatingCategory ORDER BY t.OrderForExp
					) / EggMeasureUnit, 3) AS PersonAmount, IsMain
		FROM (
			SELECT Detail.FoodID, Detail.Name, v_fooMenu.NomenclatureID, v_fooMenu.UnitMeasure, v_fooMenu.EatingTime, v_fooMenu.EatingTimeID, v_fooMenu.
				MenuId, v_fooMenu.MenuDate, v_fooMenu.ObjectID, v_fooMenu.[Object], v_fooMenu.UltraShortName, v_fooMenu.EatingCategoryID, v_fooMenu.
				EatingCategory, v_fooMenu.PortionCount, v_fooMenu.PortionCountFact, v_fooMenu.ControlPortionCount, v_fooMenu.Recipe, v_fooMenu.
				OriginalRecipe, v_fooMenu.RecipeID, v_fooMenu.Netto, RecipeLossOriginal AS RecipeLoss, BoilLoss, 
				CASE WHEN OrderForExp = max(OrderForExp) OVER (PARTITION BY DocDetailFoodID, DocDetailFoodPercent)
						AND ROW_NUMBER() OVER (
							PARTITION BY DocDetailFoodID, OrderForExp, ISNULL(SkyRecipeLoss, 1) * DocDetailLossPercent, 
								DocDetailFoodPercent 
							ORDER BY BruttoSkyFood / (1 - DocDetailLossPercent / 100.00), 
								OrderNumber DESC/*номер рецепта в меню категории*/, RecipeID)
							 = COUNT(1) OVER (PARTITION BY DocDetailFoodID, OrderForExp, ISNULL(SkyRecipeLoss, 1) * DocDetailLossPercent, DocDetailFoodPercent)
						THEN (ISNULL(DocDetailAmount, 0) - SUM(BruttoSkyFood*DocDetailFoodPercent/(1 - DocDetailLossPercent/100.00
										) * AllPortionCount) OVER (
									PARTITION BY DocDetailFoodID, ISNULL(SkyRecipeLoss, 1) * DocDetailLossPercent, DocDetailFoodPercent 
										ORDER BY OrderForExp ASC, BruttoSkyFood / (1 - DocDetailLossPercent / 100.00
											) ASC, OrderNumber DESC, RecipeID
									)
								) / AllPortionCount + BruttoSkyFood/(1 - DocDetailLossPercent / 100.00)*DocDetailFoodPercent
							
					ELSE BruttoSkyFood/(1 - DocDetailLossPercent / 100.00)*DocDetailFoodPercent 
					END AS BruttoByRecalcPlan, Detail.FoodPercent, ISNULL(SkyRecipeLoss, 1) * Detail.LossPercent AS LossPercent, 
					ISNULL(SkyRecipeLoss, 1) * DocDetailDopLossPercent AS DopLossPercent, 
					Detail.LossPercent AS 
				DocLossPercent, 0 AS BruttoByRecalcFact, 
				CASE WHEN DocDetailDopFoodID = Detail.FoodID
						AND DocDetailDopLossPercent = Detail.LossPercent
						THEN CASE 
								WHEN MenuCorrectionTypeID = 1
									AND (AllPortionCountFact - AllPortionCount) <> 0
									THEN CASE 
											WHEN OrderForExp = MAX(OrderForExp) OVER (PARTITION BY v_fooMenu.FoodID, DocDetailDopFoodPercent)
												AND ROW_NUMBER() OVER (
																PARTITION BY v_fooMenu.FoodID, OrderForExp, ISNULL(SkyRecipeLoss, 1) * 
																	DocDetailDopLossPercent, DocDetailDopFoodPercent, MenuCorrectionTypeID 
																ORDER BY BruttoSkyFood / (1 - DocDetailDopLossPercent / 100.00), 
																	OrderNumber DESC, RecipeID)
													= COUNT(1) 	 OVER (
																PARTITION BY v_fooMenu.FoodID, OrderForExp, ISNULL(SkyRecipeLoss, 1) * 
																	DocDetailDopLossPercent, DocDetailDopFoodPercent, MenuCorrectionTypeID)
												THEN (ISNULL(DocDetailDopAmount, 0) 
														- SUM(BruttoSkyFood*DocDetailDopFoodPercent/(1 - DocDetailDopLossPercent/100.00)
																* (AllPortionCountFact - AllPortionCount))
															OVER (
															PARTITION BY v_fooMenu.FoodID, ISNULL(SkyRecipeLoss, 1) * 
																DocDetailDopLossPercent, DocDetailDopFoodPercent, MenuCorrectionTypeID 
															ORDER BY OrderForExp, BruttoSkyFood / (1 - DocDetailDopLossPercent / 100.00), OrderNumber DESC, RecipeID)
													 ) / (AllPortionCountFact - AllPortionCount)
														 + BruttoSkyFood/(1 - DocDetailDopLossPercent/100.00)*DocDetailDopFoodPercent 
											ELSE BruttoSkyFood/(1 - DocDetailDopLossPercent/100.00)*DocDetailDopFoodPercent 
											END
								ELSE 0
								END
					ELSE 0
					END AS BruttoByRecalcDop, OrderNumberEatingCategory, v_fooMenu.Brutto, v_fooMenu.FoodLoss, Detail.Price AS Price, KoefToNorm, 
				MenuNumber, SignDate, PortionCount24, v_fooMenu.PersonPortionCount, v_fooMenu.NettoRecipe, v_fooMenu.ParentMenuCategoryTimeRecipeID, 
				v_fooMenu.MenuCategoryTimeRecipeID, v_fooMenu.IsHeat, v_fooMenu.OrderNumber, v_fooMenu.MenuCorrectionTypeID, IsVisible, Detail.FoodID 
				AS DocFoodID, Detail.EggMeasureUnit, 
				IIF(DocDetailFoodID=189, ROUND(ISNULL(DocDetailAmount, 0)/DocDetailEggMeasureUnit, 0),ISNULL(DocDetailAmount, 0)/DocDetailEggMeasureUnit) AS ExpAmount, 
				CASE 
					WHEN DocDetailDopFoodID = Detail.FoodID
						THEN IIF(DocDetailDopFoodID=189, ROUND(ISNULL(DocDetailDopAmount, 0)/DocDetailDopEggMeasureUnit, 0)
									,ISNULL(DocDetailDopAmount, 0)/DocDetailDopEggMeasureUnit)
					ELSE 0
					END AS ExpAmountDop, v_fooMenu.RoundTo, OrderForExp, 
					max(OrderForExp) OVER (PARTITION BY v_fooMenu.FoodID, ISNULL(SkyRecipeLoss, 1) * (DocDetailLossPercent)) AS MainOrderForExp, 
					max(IIF(MenuCorrectionTypeID=1, OrderForExp, 0)) OVER (PARTITION BY v_fooMenu.FoodID, ISNULL(SkyRecipeLoss, 1) * (DocDetailLossPercent)) AS MainOrderForExpDop, 
				Detail.MeasureUnitString, Detail.Food1C, EatingCategory1C, Detail.IsMain
			FROM v_fooMenu
			LEFT JOIN [dbo].[f_fooMenuFullJoinDetail](@MenuId) AS Detail --все расходы (3 и 7 типа), связанные с этим меню
				ON Detail.NomenclatureID = v_fooMenu.NomenclatureID
			WHERE ISNULL(Detail.Amount, 0) <> 0
				AND NettoRecipe <> 0
				AND (PortionCount + PersonPortionCount + PortionCount24) <> 0
				AND v_fooMenu.IsFromStorage = 1
				AND v_fooMenu.MenuId = @MenuId
				AND v_fooMenu.EatingCategoryID NOT IN (12, 13)
			) AS t
		INNER JOIN fooEatingCategory
			ON MainOrderForExp = fooEatingCategory.OrderForExp
		INNER JOIN fooEatingCategory fooEatingCategoryDop
			ON MainOrderForExpDop = fooEatingCategoryDop.OrderForExp
	RETURN
END

GO

ALTER VIEW [dbo].[v_fooMenu]
AS
SELECT fooFood.FoodID, fooFood.Name, fooFood.NomenclatureID, fooUnitMeasure.Name AS UnitMeasure, fooEatingTime.Name AS EatingTime, 
        fooEatingTime.EatingTimeID, fooMenu.MenuID, fooMenu.MenuDate, fooMenu.ObjectID, glbObject.ShortName AS Object, glbObject.UltraShortName AS UltraShortName, 
        fooEatingCategory.EatingCategoryID, fooEatingCategory.Name AS EatingCategory, fooMenuCategoryTimeRecipe.PortionCount, 
        fooMenuCategoryTimeRecipe.PortionCountFact, fooMenuCategoryTimeRecipe.ControlPortionCount, fooRecipe.Name AS Recipe, 
        fooRecipe.OriginalName AS OriginalRecipe, fooRecipe.RecipeID, fooMenuCategoryTimeRecipe.Netto AS NettoRecipe /*нетто блюда в меню*/, 
        fooRecipe.Netto AS fooRecipe_Netto /*нетто блюда по рецепту*/, fooMenuCategoryTimeRecipe.ParentMenuCategoryTimeRecipeID, 
        fooMenuCategoryTimeRecipe.MenuCategoryTimeRecipeID, fooFoodRecipe.IsHeat, fooMenuCategoryTimeRecipe.OrderNumber, 
        fooMenuCategoryTimeRecipe.MenuCorrectionTypeID, fooUnitMeasure.KoefToGramm, fooRecipe.IsVisible, 
        ROUND(fooFoodRecipe.Netto * (fooMenuCategoryTimeRecipe.Netto / fooRecipe.Netto) / fooUnitMeasure.KoefToNorm,5) AS Netto/*нетто продукта в меню*/, 
        /*брутто продукта в меню как нетто с учетом всех потерь*/
		((fooFoodRecipe.Netto * (fooMenuCategoryTimeRecipe.Netto / fooRecipe.Netto))
		/(1.0 - ISNULL(fooFoodRecipe.PercentValue, fooFoodLoss.PercentValue) / 100.0)) 
		/(1.0 - fooFoodRecipe.IsBoilLoss * fooFoodLoss.BoilLoss / 100.0) / fooUnitMeasure.KoefToNorm AS Brutto, 
		/*учитываем только проценты потерь и уварку из рецепта, если не указано в рецепте - справочное игнорируем
		смысл - сколько нужно "идеальных продуктов" для рецепта, "неидеальность продукта остается только в справочнике (и приходе)"*/
		((fooFoodRecipe.Netto * fooMenuCategoryTimeRecipe.Netto / fooRecipe.Netto) 
		/(1.0 - ISNULL(fooFoodRecipe.PercentValue, 0.0) / 100.0)) 
        /(1.0 - fooFoodRecipe.IsBoilLoss * fooFoodLoss.BoilLoss / 100.0) / fooUnitMeasure.KoefToNorm AS BruttoSkyFood,
		/*isIncPercent: 1 - % отходов берется из прихода 2 - из рецепта 3 - не м.б. отходов 4 - перемножение из прихода и из рецепта*/ 
		((fooFoodRecipe.Netto * fooMenuCategoryTimeRecipe.Netto / fooRecipe.Netto) 
		/(1.0 - case when fooFoodObject.isIncPercent in (2,4) then ISNULL(fooFoodRecipe.PercentValue, 0.0) else 0 end / 100.0))
		/(1.0 - case when fooFood.FoodID in (66,192,308) then fooFoodLoss.PercentValue else case when fooFoodObject.isIncPercent in (1,4) 
																								then ISNULL(fooFoodObject.LossPercent, 0.0) else 0 end end / 100.0) 
        /(1.0 - fooFoodRecipe.IsBoilLoss * fooFoodLoss.BoilLoss / 100.0) / fooUnitMeasure.KoefToNorm AS BruttoSkyFoodObject,
        /*"недобрутто" - нетто увеличенное с учетом уварки*/
		(fooFoodRecipe.Netto * fooMenuCategoryTimeRecipe.Netto / fooRecipe.Netto) 
		/(1.0 - fooFoodRecipe.IsBoilLoss * fooFoodLoss.BoilLoss / 100.0)/fooUnitMeasure.KoefToNorm AS BruttoWithoutFoodLoss,
		fooFoodRecipe.PercentValue AS RecipeLossOriginal /*потери, указанные непосредственно в рецепте (они в приоритете)*/, 
		1.0 - fooFoodRecipe.PercentValue / 100.0 AS RecipeLoss /*остаток от потерь, мультипликатор*/, 
        ISNULL(fooFoodRecipe.PercentValue, fooFoodLoss.PercentValue) AS FoodLoss, 
		(CASE ISNULL(fooFoodRecipe.IsBoilLoss, 0) WHEN 1 THEN (1.0 - fooFoodLoss.BoilLoss / 100.0) ELSE 1 END) AS BoilLoss, 
		ISNULL(fooMenuCategoryTimeRecipe.PersonPortionCount, 0) AS PersonPortionCount, 
		ISNULL(fooMenuCategoryTimeRecipe.PortionCount24, 0) AS PortionCount24, 
		ISNULL(fooMenuCategoryTimeRecipe.PortionCountFact24, 0) AS PortionCountFact24,
        fooMenuCategoryTimeRecipe.PortionCount + fooMenuCategoryTimeRecipe.ControlPortionCount
		+ ISNULL(fooMenuCategoryTimeRecipe.PersonPortionCount, 0)+ISNULL(fooMenuCategoryTimeRecipe.PortionCount24, 0) AS AllPortionCount, 
        fooMenuCategoryTimeRecipe.PortionCountFact + fooMenuCategoryTimeRecipe.ControlPortionCount 
		+ ISNULL(fooMenuCategoryTimeRecipe.PersonPortionCount, 0) AS AllPortionCountFact, 
		fooFoodObject.RoundTo, fooMenu.DayNumber, fooRecipe.RecipeSourceID, fooMenu.MenuStatusID, 
		fooFood.IsFromStorage, fooFoodRecipe.Netto AS FoodNettoFromRecipe, fooEatingCategory.OrderForExp, 
        CASE WHEN fooFoodRecipe.PercentValue IS NULL THEN NULL ELSE 1.0 END AS SkyRecipeLoss, 
		fooUnitMeasure.KoefToNorm, fooEatingTime.OrderNumber as OrderNumberEatingCategory,
		fooFood.KoefForNorm, foofoodobject.IsUndividedPack,fooUnitMeasure.KoefToNorm as fooUnitMeasureKoefToNorm,
		MenuNumber, SignDate, fooFood.Code1C as Food1C, fooEatingCategory.Code1C as EatingCategory1C, fooFoodRecipe.FoodRecipeID
FROM fooMenu INNER JOIN
        fooMenuCategory ON fooMenu.MenuID = fooMenuCategory.MenuID INNER JOIN
        fooMenuCategoryTimeRecipe ON fooMenuCategory.MenuCategoryID = fooMenuCategoryTimeRecipe.MenuCategoryID INNER JOIN
        fooRecipe ON fooRecipe.RecipeID = fooMenuCategoryTimeRecipe.RecipeID INNER JOIN
        fooFoodRecipe ON fooRecipe.RecipeID = fooFoodRecipe.RecipeID INNER JOIN
        fooFood ON fooFood.FoodID = fooFoodRecipe.FoodID INNER JOIN
		foofoodobject on fooFood.FoodID = foofoodobject.FoodID and foofoodobject.ObjectID = fooMenu.ObjectID inner join 
        fooUnitMeasure ON fooFood.UnitMeasureID = fooUnitMeasure.UnitMeasureID INNER JOIN
        fooEatingTime ON fooEatingTime.EatingTimeID = fooMenuCategoryTimeRecipe.EatingTimeID INNER JOIN
        glbObject ON fooMenu.ObjectID = glbObject.ObjectID INNER JOIN
        fooEatingCategory ON fooMenuCategory.EatingCategoryID = fooEatingCategory.EatingCategoryID INNER JOIN
        fooFoodLoss ON fooFood.FoodID = fooFoodLoss.FoodID AND ISNULL(fooFoodLoss.MonthID, MONTH(fooMenu.MenuDate)) 
        = MONTH(fooMenu.MenuDate)
WHERE fooMenu.RecordStatusID = 1 AND fooMenuCategory.RecordStatusID = 1 AND fooMenuCategoryTimeRecipe.RecordStatusID = 1 AND 
                      fooFoodRecipe.RecordStatusID = 1


GO