------------------------------------------------------------------------------
--	FILE:	 Pangaea.lua
--	AUTHOR:  Bob Thomas
--	PURPOSE: Global map script - Simulates a Pan-Earth Supercontinent.
--           This is one of Civ5's featured map scripts.
------------------------------------------------------------------------------
--	Copyright (c) 2010 Firaxis Games, Inc. All rights reserved.
------------------------------------------------------------------------------

include("MapGenerator");
include("FractalWorld");
include("FeatureGenerator");
include("TerrainGenerator");

------------------------------------------------------------------------------
function GetMapScriptInfo()
	local world_age, temperature, rainfall, sea_level, resources = GetCoreMapOptions()
	return {
		Name = "Better Pangaea V4.1",
		Description = "TXT_KEY_MAP_PANGAEA_HELP",
		IsAdvancedMap = false,
		IconIndex = 0,
		SortIndex = 2,
		CustomOptions = {world_age, temperature, rainfall, sea_level, 
			{
				Name = "TXT_KEY_MAP_OPTION_RESOURCES",	-- Customizing the Resource setting to Default to Strategic Balance.
				Values = {
					"TXT_KEY_MAP_OPTION_SPARSE",
					"TXT_KEY_MAP_OPTION_STANDARD",
					"TXT_KEY_MAP_OPTION_ABUNDANT",
					"TXT_KEY_MAP_OPTION_LEGENDARY_START",
					"TXT_KEY_MAP_OPTION_STRATEGIC_BALANCE",
					"Strategic Balance With Coal",
					"TXT_KEY_MAP_OPTION_RANDOM",
				},
				DefaultValue = 6,
				SortPriority = -95,
			},
			{
				Name = "Saturation",
				Values = {
					"0.3",
					"0.5",
					"0.65",
					"0.8",
					"1",
					"1.5",
				},
				DefaultValue = 5,
				SortPriority = -96,
			},
			{
				Name = "Start",
				Values = {
					"Better Start",
					"Normal Start",
				},
				DefaultValue = 2,
				SortPriority = -97,
			}
		},
	}
end
------------------------------------------------------------------------------

------------------------------------------------------------------------------
------------------------------------------------------------------------------
PangaeaFractalWorld = {};
------------------------------------------------------------------------------
function PangaeaFractalWorld.Create(fracXExp, fracYExp)
	local gridWidth, gridHeight = Map.GetGridSize();
	
	local data = {
		InitFractal = FractalWorld.InitFractal,
		ShiftPlotTypes = FractalWorld.ShiftPlotTypes,
		ShiftPlotTypesBy = FractalWorld.ShiftPlotTypesBy,
		DetermineXShift = FractalWorld.DetermineXShift,
		DetermineYShift = FractalWorld.DetermineYShift,
		GenerateCenterRift = FractalWorld.GenerateCenterRift,
		GeneratePlotTypes = PangaeaFractalWorld.GeneratePlotTypes,	-- Custom method
		
		iFlags = Map.GetFractalFlags(),
		
		fracXExp = fracXExp,
		fracYExp = fracYExp,
		
		iNumPlotsX = gridWidth,
		iNumPlotsY = gridHeight,
		plotTypes = table.fill(PlotTypes.PLOT_OCEAN, gridWidth * gridHeight)
	};
		
	return data;
end	
------------------------------------------------------------------------------
function PangaeaFractalWorld:GeneratePlotTypes(args)
	if(args == nil) then args = {}; end
	
	local sea_level_low = 63;
	local sea_level_normal = 68;
	local sea_level_high = 73;
	local world_age_old = 2;
	local world_age_normal = 3;
	local world_age_new = 5;
	--
	local extra_mountains = 6;
	local grain_amount = 3;
	local adjust_plates = 1.3;
	local shift_plot_types = true;
	local tectonic_islands = true;
	local hills_ridge_flags = self.iFlags;
	local peaks_ridge_flags = self.iFlags;
	local has_center_rift = false;
	
	local sea_level = Map.GetCustomOption(4)
	if sea_level == 4 then
		sea_level = 1 + Map.Rand(3, "Random Sea Level - Lua");
	end
	local world_age = Map.GetCustomOption(1)
	if world_age == 4 then
		world_age = 1 + Map.Rand(3, "Random World Age - Lua");
	end

	-- Set Sea Level according to user selection.
	local water_percent = sea_level_normal;
	if sea_level == 1 then -- Low Sea Level
		water_percent = sea_level_low
	elseif sea_level == 3 then -- High Sea Level
		water_percent = sea_level_high
	else -- Normal Sea Level
	end

	-- Set values for hills and mountains according to World Age chosen by user.
	local adjustment = world_age_normal;
	if world_age == 3 then -- 5 Billion Years
		adjustment = world_age_old;
		adjust_plates = adjust_plates * 0.75;
	elseif world_age == 1 then -- 3 Billion Years
		adjustment = world_age_new;
		adjust_plates = adjust_plates * 1.5;
	else -- 4 Billion Years
	end
	-- Apply adjustment to hills and peaks settings.
	local hillsBottom1 = 28 - adjustment;
	local hillsTop1 = 28 + adjustment;
	local hillsBottom2 = 72 - adjustment;
	local hillsTop2 = 72 + adjustment;
	local hillsClumps = 1 + adjustment;
	local hillsNearMountains = 91 - (adjustment * 2) - extra_mountains;
	local mountains = 97 - adjustment - extra_mountains;

	-- Hills and Mountains handled differently according to map size - Bob
	local WorldSizeTypes = {};
	for row in GameInfo.Worlds() do
		WorldSizeTypes[row.Type] = row.ID;
	end
	local sizekey = Map.GetWorldSize();
	-- Fractal Grains
	local sizevalues = {
		[WorldSizeTypes.WORLDSIZE_DUEL]     = 3,
		[WorldSizeTypes.WORLDSIZE_TINY]     = 3,
		[WorldSizeTypes.WORLDSIZE_SMALL]    = 4,
		[WorldSizeTypes.WORLDSIZE_STANDARD] = 4,
		[WorldSizeTypes.WORLDSIZE_LARGE]    = 5,
		[WorldSizeTypes.WORLDSIZE_HUGE]		= 5
	};
	local grain = sizevalues[sizekey] or 3;
	-- Tectonics Plate Counts
	local platevalues = {
		[WorldSizeTypes.WORLDSIZE_DUEL]		= 6,
		[WorldSizeTypes.WORLDSIZE_TINY]     = 9,
		[WorldSizeTypes.WORLDSIZE_SMALL]    = 12,
		[WorldSizeTypes.WORLDSIZE_STANDARD] = 18,
		[WorldSizeTypes.WORLDSIZE_LARGE]    = 24,
		[WorldSizeTypes.WORLDSIZE_HUGE]     = 30
	};
	local numPlates = platevalues[sizekey] or 5;
	-- Add in any plate count modifications passed in from the map script. - Bob
	numPlates = numPlates * adjust_plates;

	-- Generate continental fractal layer and examine the largest landmass. Reject
	-- the result until the largest landmass occupies 84% or more of the total land.
	local done = false;
	local iAttempts = 0;
	local iWaterThreshold, biggest_area, iNumTotalLandTiles, iNumBiggestAreaTiles, iBiggestID;
	while done == false do
		local grain_dice = Map.Rand(7, "Continental Grain roll - LUA Pangaea");
		if grain_dice < 4 then
			grain_dice = 1;
		else
			grain_dice = 2;
		end
		local rift_dice = Map.Rand(3, "Rift Grain roll - LUA Pangaea");
		if rift_dice < 1 then
			rift_dice = -1;
		end
		
		self.continentsFrac = nil;
		self:InitFractal{continent_grain = grain_dice, rift_grain = rift_dice};
		iWaterThreshold = self.continentsFrac:GetHeight(water_percent);
		
		iNumTotalLandTiles = 0;
		for x = 0, self.iNumPlotsX - 1 do
			for y = 0, self.iNumPlotsY - 1 do
				local i = y * self.iNumPlotsX + x;
				local val = self.continentsFrac:GetHeight(x, y);
				if(val <= iWaterThreshold) then
					self.plotTypes[i] = PlotTypes.PLOT_OCEAN;
				else
					self.plotTypes[i] = PlotTypes.PLOT_LAND;
					iNumTotalLandTiles = iNumTotalLandTiles + 1;
				end
			end
		end

		SetPlotTypes(self.plotTypes);
		Map.RecalculateAreas();
		
		biggest_area = Map.FindBiggestArea(false);
		iNumBiggestAreaTiles = biggest_area:GetNumTiles();
		-- Now test the biggest landmass to see if it is large enough.
		if iNumBiggestAreaTiles >= iNumTotalLandTiles * 0.84 then
			done = true;
			iBiggestID = biggest_area:GetID();
		end
		iAttempts = iAttempts + 1;
		
		--[[ Printout for debug use only
		print("-"); print("--- Pangaea landmass generation, Attempt#", iAttempts, "---");
		print("- This attempt successful: ", done);
		print("- Total Land Plots in world:", iNumTotalLandTiles);
		print("- Land Plots belonging to biggest landmass:", iNumBiggestAreaTiles);
		print("- Percentage of land belonging to Pangaea: ", 100 * iNumBiggestAreaTiles / iNumTotalLandTiles);
		print("- Continent Grain for this attempt: ", grain_dice);
		print("- Rift Grain for this attempt: ", rift_dice);
		print("- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -");
		print(".");
		]]--
	end
	
	-- Generate fractals to govern hills and mountains
	self.hillsFrac = Fractal.Create(self.iNumPlotsX, self.iNumPlotsY, grain, self.iFlags, self.fracXExp, self.fracYExp);
	self.mountainsFrac = Fractal.Create(self.iNumPlotsX, self.iNumPlotsY, grain, self.iFlags, self.fracXExp, self.fracYExp);
	self.hillsFrac:BuildRidges(numPlates, hills_ridge_flags, 1, 2);
	self.mountainsFrac:BuildRidges((numPlates * 2) / 3, peaks_ridge_flags, 6, 1);
	-- Get height values
	local iHillsBottom1 = self.hillsFrac:GetHeight(hillsBottom1);
	local iHillsTop1 = self.hillsFrac:GetHeight(hillsTop1);
	local iHillsBottom2 = self.hillsFrac:GetHeight(hillsBottom2);
	local iHillsTop2 = self.hillsFrac:GetHeight(hillsTop2);
	local iHillsClumps = self.mountainsFrac:GetHeight(hillsClumps);
	local iHillsNearMountains = self.mountainsFrac:GetHeight(hillsNearMountains);
	local iMountainThreshold = self.mountainsFrac:GetHeight(mountains);
	local iPassThreshold = self.hillsFrac:GetHeight(hillsNearMountains);
	-- Get height values for tectonic islands
	local iMountain100 = self.mountainsFrac:GetHeight(100);
	local iMountain99 = self.mountainsFrac:GetHeight(99);
	local iMountain97 = self.mountainsFrac:GetHeight(97);
	local iMountain95 = self.mountainsFrac:GetHeight(95);

	-- Because we haven't yet shifted the plot types, we will not be able to take advantage 
	-- of having water and flatland plots already set. We still have to generate all data
	-- for hills and mountains, too, then shift everything, then set plots one more time.
	for x = 0, self.iNumPlotsX - 1 do
		for y = 0, self.iNumPlotsY - 1 do
		
			local i = y * self.iNumPlotsX + x;
			local val = self.continentsFrac:GetHeight(x, y);
			local mountainVal = self.mountainsFrac:GetHeight(x, y);
			local hillVal = self.hillsFrac:GetHeight(x, y);
	
			if(val <= iWaterThreshold) then
				self.plotTypes[i] = PlotTypes.PLOT_OCEAN;
				
				if tectonic_islands then -- Build islands in oceans along tectonic ridge lines - Brian
					if (mountainVal == iMountain100) then -- Isolated peak in the ocean
						self.plotTypes[i] = PlotTypes.PLOT_MOUNTAIN;
					elseif (mountainVal == iMountain99) then
						self.plotTypes[i] = PlotTypes.PLOT_HILLS;
					elseif (mountainVal == iMountain97) or (mountainVal == iMountain95) then
						self.plotTypes[i] = PlotTypes.PLOT_LAND;
					end
				end
					
			else
				if (mountainVal >= iMountainThreshold) then
					if (hillVal >= iPassThreshold) then -- Mountain Pass though the ridgeline - Brian
						self.plotTypes[i] = PlotTypes.PLOT_HILLS;
					else -- Mountain
						self.plotTypes[i] = PlotTypes.PLOT_MOUNTAIN;
					end
				elseif (mountainVal >= iHillsNearMountains) then
					self.plotTypes[i] = PlotTypes.PLOT_HILLS; -- Foot hills - Bob
				else
					if ((hillVal >= iHillsBottom1 and hillVal <= iHillsTop1) or (hillVal >= iHillsBottom2 and hillVal <= iHillsTop2)) then
						self.plotTypes[i] = PlotTypes.PLOT_HILLS;
					else
						self.plotTypes[i] = PlotTypes.PLOT_LAND;
					end
				end
			end
		end
	end

	self:ShiftPlotTypes();
	
	-- Now shift everything toward one of the poles, to reduce how much jungles tend to dominate this script.
	local shift_dice = Map.Rand(2, "Shift direction - LUA Pangaea");
	local iStartRow, iNumRowsToShift;
	local bFoundPangaea, bDoShift = false, false;
	if shift_dice == 1 then
		-- Shift North
		for y = self.iNumPlotsY - 2, 1, -1 do
			for x = 0, self.iNumPlotsX - 1 do
				local i = y * self.iNumPlotsX + x;
				if self.plotTypes[i] == PlotTypes.PLOT_HILLS or self.plotTypes[i] == PlotTypes.PLOT_LAND then
					local plot = Map.GetPlot(x, y);
					local iAreaID = plot:GetArea();
					if iAreaID == iBiggestID then
						bFoundPangaea = true;
						iStartRow = y + 1;
						if iStartRow < self.iNumPlotsY - 4 then -- Enough rows of water space to do a shift.
							bDoShift = true;
						end
						break
					end
				end
			end
			-- Check to see if we've found the Pangaea.
			if bFoundPangaea == true then
				break
			end
		end
	else
		-- Shift South
		for y = 1, self.iNumPlotsY - 2 do
			for x = 0, self.iNumPlotsX - 1 do
				local i = y * self.iNumPlotsX + x;
				if self.plotTypes[i] == PlotTypes.PLOT_HILLS or self.plotTypes[i] == PlotTypes.PLOT_LAND then
					local plot = Map.GetPlot(x, y);
					local iAreaID = plot:GetArea();
					if iAreaID == iBiggestID then
						bFoundPangaea = true;
						iStartRow = y - 1;
						if iStartRow > 3 then -- Enough rows of water space to do a shift.
							bDoShift = true;
						end
						break
					end
				end
			end
			-- Check to see if we've found the Pangaea.
			if bFoundPangaea == true then
				break
			end
		end
	end
	if bDoShift == true then
		if shift_dice == 1 then -- Shift North
			local iRowsDifference = self.iNumPlotsY - iStartRow - 2;
			local iRowsInPlay = math.floor(iRowsDifference * 0.7);
			local iRowsBase = math.ceil(iRowsDifference * 0.3);
			local rows_dice = Map.Rand(iRowsInPlay, "Number of Rows to Shift - LUA Pangaea");
			local iNumRows = math.min(iRowsDifference - 1, iRowsBase + rows_dice);
			local iNumEvenRows = 2 * math.floor(iNumRows / 2); -- MUST be an even number or we risk breaking a 1-tile isthmus and splitting the Pangaea.
			local iNumRowsToShift = math.max(2, iNumEvenRows);
			--print("-"); print("Shifting lands northward by this many plots: ", iNumRowsToShift); print("-");
			-- Process from top down.
			for y = (self.iNumPlotsY - 1) - iNumRowsToShift, 0, -1 do
				for x = 0, self.iNumPlotsX - 1 do
					local sourcePlotIndex = y * self.iNumPlotsX + x + 1;
					local destPlotIndex = (y + iNumRowsToShift) * self.iNumPlotsX + x + 1;
					self.plotTypes[destPlotIndex] = self.plotTypes[sourcePlotIndex]
				end
			end
			for y = 0, iNumRowsToShift - 1 do
				for x = 0, self.iNumPlotsX - 1 do
					local i = y * self.iNumPlotsX + x + 1;
					self.plotTypes[i] = PlotTypes.PLOT_OCEAN;
				end
			end
		else -- Shift South
			local iRowsDifference = iStartRow - 1;
			local iRowsInPlay = math.floor(iRowsDifference * 0.7);
			local iRowsBase = math.ceil(iRowsDifference * 0.3);
			local rows_dice = Map.Rand(iRowsInPlay, "Number of Rows to Shift - LUA Pangaea");
			local iNumRows = math.min(iRowsDifference - 1, iRowsBase + rows_dice);
			local iNumEvenRows = 2 * math.floor(iNumRows / 2); -- MUST be an even number or we risk breaking a 1-tile isthmus and splitting the Pangaea.
			local iNumRowsToShift = math.max(2, iNumEvenRows);
			--print("-"); print("Shifting lands southward by this many plots: ", iNumRowsToShift); print("-");
			-- Process from bottom up.
			for y = 0, (self.iNumPlotsY - 1) - iNumRowsToShift do
				for x = 0, self.iNumPlotsX - 1 do
					local sourcePlotIndex = (y + iNumRowsToShift) * self.iNumPlotsX + x + 1;
					local destPlotIndex = y * self.iNumPlotsX + x + 1;
					self.plotTypes[destPlotIndex] = self.plotTypes[sourcePlotIndex]
				end
			end
			for y = self.iNumPlotsY - iNumRowsToShift, self.iNumPlotsY - 1 do
				for x = 0, self.iNumPlotsX - 1 do
					local i = y * self.iNumPlotsX + x + 1;
					self.plotTypes[i] = PlotTypes.PLOT_OCEAN;
				end
			end
		end
	end

	return self.plotTypes;
end
------------------------------------------------------------------------------

------------------------------------------------------------------------------
function GeneratePlotTypes()
	-- Plot generation customized to ensure enough land belongs to the Pangaea.
	print("Generating Plot Types (Lua Pangaea) ...");
	
	local fractal_world = PangaeaFractalWorld.Create();
	local plotTypes = fractal_world:GeneratePlotTypes();
	
	SetPlotTypes(plotTypes);
	GenerateCoasts();
end
------------------------------------------------------------------------------
function GenerateTerrain()
	
	-- Get Temperature setting input by user.
	local temp = Map.GetCustomOption(2)
	local iDesertPer = 32; -- 32
	local iPlainsPer = 50; -- Deserts are processed first, so Plains will take this percentage of whatever remains. - Bob
	local fSnowLat = 0.75; -- 0.75
	local fTundraLat = 0.6; -- 0.6
	local temp = Map.GetCustomOption(2)
	if temp == 4 then
		temp = 1 + Map.Rand(3, "Random Temperature - Lua");
	end

	local args = {
		temperature = temp,
		iDesertPercent = iDesertPer,
		-- iPlainsPercent = iPlainsPer,
		fSnowLatitude = fSnowLat,
		fTundraLatitude = fTundraLat
		};
	local terraingen = TerrainGenerator.Create(args);

	terrainTypes = terraingen:GenerateTerrain();
	
	SetTerrainTypes(terrainTypes);
end
------------------------------------------------------------------------------
function AddFeatures()
	print("Adding Features (Lua Pangaea) ...");

	-- Get Rainfall setting input by user.
	local rain = Map.GetCustomOption(3)
	if rain == 4 then
		rain = 1 + Map.Rand(3, "Random Rainfall - Lua");
	end
	
	local args = {rainfall = rain}
	local featuregen = FeatureGenerator.Create(args);

	-- False parameter removes mountains from coastlines.
	featuregen:AddFeatures(false);
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceStrategicAndBonusResources()
	-- KEY: {Resource ID, Quantity (0 = unquantified), weighting, minimum radius, maximum radius}
	-- KEY: (frequency (1 per n plots in the list), impact list number, plot list, resource data)
	--
	-- The radius creates a zone around the plot that other resources of that
	-- type will avoid if possible. See ProcessResourceList for impact numbers.
	--
	-- Order of placement matters, so changing the order may affect a later dependency.
	
	-- Adjust amounts, if applicable, based on Resource Setting.
	local uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = self:GetMajorStrategicResourceQuantityValues()
	local res = Map.GetCustomOption(5)
	local sat = Map.GetCustomOption(6)

	-- Adjust appearance rate per Resource Setting chosen by user.
	local bonus_multiplier;

	if sat == 1 then
		bonus_multiplier = 0.3;
	elseif sat == 2 then
		bonus_multiplier = 0.5;
	elseif sat == 3 then
		bonus_multiplier = 0.65;
	elseif sat == 4 then
		bonus_multiplier = 0.8;
	elseif sat == 5 then
		bonus_multiplier = 1;
	elseif sat == 6 then
		bonus_multiplier = 1.5;
	end

	--[[ if res == 1 then -- Sparse, so increase the number of tiles per bonus.
		bonus_multiplier = 1.5;
	elseif res == 3 then -- Abundant, so reduce the number of tiles per bonus.
		bonus_multiplier = 0.66667;
	end --]]

	-- Place Strategic resources.
	print("Map Generation - Placing Strategics");
	local resources_to_place = {
	{self.oil_ID, oil_amt, 65, 1, 4},
	{self.uranium_ID, uran_amt, 35, 1, 4} };
	self:ProcessResourceList(7, 1, self.marsh_list, resources_to_place)

	local resources_to_place = {
	{self.oil_ID, oil_amt, 55, 1, 5},
	{self.aluminum_ID, alum_amt, 15, 1, 2},
	{self.iron_ID, iron_amt, 35, 1, 2} };
	self:ProcessResourceList(16, 1, self.tundra_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.oil_ID, oil_amt, 65, 1, 5},
	{self.aluminum_ID, alum_amt, 15, 1, 2},
	{self.iron_ID, iron_amt, 20, 1, 2} };
	self:ProcessResourceList(15, 1, self.snow_flat_list, resources_to_place)

	local resources_to_place = {
	{self.oil_ID, oil_amt, 70, 1, 2},
	{self.iron_ID, iron_amt, 30, 1, 2} };
	self:ProcessResourceList(11, 1, self.desert_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.iron_ID, iron_amt, 26, 1, 3},
	{self.coal_ID, coal_amt, 35, 1, 3},
	{self.aluminum_ID, alum_amt, 39, 1, 3} };
	self:ProcessResourceList(22, 1, self.hills_list, resources_to_place)

	local resources_to_place = {
	{self.coal_ID, coal_amt, 30, 1, 2},
	{self.uranium_ID, uran_amt, 70, 1, 2} };
	self:ProcessResourceList(33, 1, self.jungle_flat_list, resources_to_place)
	local resources_to_place = {
	{self.coal_ID, coal_amt, 25, 1, 2},
	{self.uranium_ID, uran_amt, 50, 10, 0} };
	self:ProcessResourceList(39, 1, self.forest_flat_list, resources_to_place)

	local resources_to_place = {
	{self.horse_ID, horse_amt, 100, 1, 5} };
	self:ProcessResourceList(10, 1, self.dry_grass_flat_no_feature, resources_to_place)
	local resources_to_place = {
	{self.horse_ID, horse_amt, 100, 1, 5} };
	self:ProcessResourceList(10, 1, self.plains_flat_no_feature, resources_to_place)

	self:AddModernMinorStrategicsToCityStates() -- Added spring 2011
	
	self:PlaceSmallQuantitiesOfStrategics(23 * bonus_multiplier, self.land_list);
	
	self:PlaceOilInTheSea();

	
	-- Check for low or missing Strategic resources
	if self.amounts_of_resources_placed[self.iron_ID + 1] < 8 then
		--print("Map has very low iron, adding another.");
		local resources_to_place = { {self.iron_ID, iron_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.hills_list, resources_to_place) -- 99999 means one per that many tiles: a single instance.
	end
	if self.amounts_of_resources_placed[self.iron_ID + 1] < 4 * self.iNumCivs then
		--print("Map has very low iron, adding another.");
		local resources_to_place = { {self.iron_ID, iron_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.land_list, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.horse_ID + 1] < 4 * self.iNumCivs then
		--print("Map has very low horse, adding another.");
		local resources_to_place = { {self.horse_ID, horse_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.plains_flat_no_feature, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.horse_ID + 1] < 4 * self.iNumCivs then
		--print("Map has very low horse, adding another.");
		local resources_to_place = { {self.horse_ID, horse_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.dry_grass_flat_no_feature, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.coal_ID + 1] < 8 then
		--print("Map has very low coal, adding another.");
		local resources_to_place = { {self.coal_ID, coal_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.hills_list, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.coal_ID + 1] < 4 * self.iNumCivs then
		--print("Map has very low coal, adding another.");
		local resources_to_place = { {self.coal_ID, coal_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.land_list, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.oil_ID + 1] < 4 * self.iNumCivs then
		--print("Map has very low oil, adding another.");
		local resources_to_place = { {self.oil_ID, oil_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.land_list, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.aluminum_ID + 1] < 4 * self.iNumCivs then
		--print("Map has very low aluminum, adding another.");
		local resources_to_place = { {self.aluminum_ID, alum_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.hills_list, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.uranium_ID + 1] < 2 * self.iNumCivs then
		--print("Map has very low uranium, adding another.");
		local resources_to_place = { {self.uranium_ID, uran_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.land_list, resources_to_place)
	end
	
	
	-- Place Bonus Resources
	print("Map Generation - Placing Bonuses");
	self:PlaceFish(10 * bonus_multiplier, self.coast_list);
	self:PlaceSexyBonusAtCivStarts()
	self:AddExtraBonusesToHillsRegions()
	
	local resources_to_place = {
	{self.deer_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(6 * bonus_multiplier, 3, self.extra_deer_list, resources_to_place)

	local resources_to_place = {
	{self.wheat_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(6 * bonus_multiplier, 3, self.desert_wheat_list, resources_to_place)

	local resources_to_place = {
	{self.deer_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(8 * bonus_multiplier, 3, self.tundra_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.banana_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(10 * bonus_multiplier, 3, self.banana_list, resources_to_place)

	local resources_to_place = {
	{self.wheat_ID, 1, 100, 1, 3} };
	self:ProcessResourceList(30 * bonus_multiplier, 3, self.plains_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.bison_ID, 1, 100, 2, 3} };
	self:ProcessResourceList(15 * bonus_multiplier, 3, self.plains_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.cow_ID, 1, 100, 2, 3} };
	self:ProcessResourceList(22 * bonus_multiplier, 3, self.grass_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.stone_ID, 1, 100, 1, 1} };
	self:ProcessResourceList(20 * bonus_multiplier, 3, self.dry_grass_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.bison_ID, 1, 100, 1, 1} };
	self:ProcessResourceList(20 * bonus_multiplier, 3, self.dry_grass_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.sheep_ID, 1, 100, 1, 1} };
	self:ProcessResourceList(20 * bonus_multiplier, 3, self.hills_open_list, resources_to_place)

	local resources_to_place = {
	{self.stone_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(10 * bonus_multiplier, 3, self.tundra_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.stone_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(16 * bonus_multiplier, 3, self.desert_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.deer_ID, 1, 100, 3, 4} };
	self:ProcessResourceList(22 * bonus_multiplier, 3, self.forest_flat_that_are_not_tundra, resources_to_place)
end
------------------------------------------------------------------------------
function AssignStartingPlots:GetIndicesForLuxuryType(resource_ID)
	-- This function will identify up to four of the fifteen "Luxury Plot Lists"
	-- (visually listed on screen directly above this text) that match terrain 
	-- best suitable for this type of luxury.
	--print("-"); print("Obtaining indices for Luxury#", resource_ID);
	local primary, secondary, tertiary, quaternary = -1, -1, -1, -1;
	if resource_ID == self.whale_ID then
		primary = 1;
	elseif resource_ID == self.pearls_ID then
		primary = 1;
	elseif resource_ID == self.gold_ID then
		primary, secondary, tertiary = 4, 5, 10;
	elseif resource_ID == self.silver_ID then
		primary, secondary, tertiary, quaternary = 4, 5, 12, 14;
	elseif resource_ID == self.gems_ID then
		primary, secondary, tertiary, quaternary = 6, 7, 4, 8;
	elseif resource_ID == self.marble_ID then
		primary, secondary, tertiary, quaternary = 12, 11, 4, 10;
	elseif resource_ID == self.ivory_ID then
		primary, secondary = 11, 12;
	elseif resource_ID == self.fur_ID then
		primary, secondary = 14, 15;
	elseif resource_ID == self.dye_ID then
		primary, secondary, tertiary = 9, 8, 7, 2;
	elseif resource_ID == self.spices_ID then
		primary, secondary, tertiary = 15, 8, 7, 2;
	elseif resource_ID == self.silk_ID then
		primary, secondary = 15, 8, 7;
	elseif resource_ID == self.sugar_ID then
		primary, secondary, tertiary, quaternary = 8, 3, 12, 2;
	elseif resource_ID == self.cotton_ID then
		primary, secondary, tertiary = 3, 4, 12, 13;
	elseif resource_ID == self.wine_ID then
		primary, secondary, tertiary = 11, 12, 13;
	elseif resource_ID == self.incense_ID then
		primary, secondary, tertiary = 3, 11, 4, 10;
	elseif resource_ID == self.copper_ID then
		primary, secondary, tertiary, quaternary = 4, 5, 12, 14;
	elseif resource_ID == self.salt_ID then
		primary, secondary, tertiary, quaternary = 11, 9, 14, 4;
	elseif resource_ID == self.citrus_ID then
		primary, secondary, tertiary, quaternary = 6, 8, 15, 3;
	elseif resource_ID == self.truffles_ID then
		primary, secondary, tertiary, quaternary = 15, 5, 8, 2;
	elseif resource_ID == self.crab_ID then
		primary = 1;
	elseif resource_ID == self.cocoa_ID then
		primary, secondary, tertiary = 8, 6, 15;
	end
	--print("Found indices of", primary, secondary, tertiary, quaternary);
	return primary, secondary, tertiary, quaternary;
end
------------------------------------------------------------------------------
function AssignStartingPlots:FixSugarJungles()
	-- Sugar could not be made to look good in both jungle and open/marsh at the same time.
	-- Jon and I decided the best workaround would be to turn any Sugar/Jungle in to Marsh.
	local iW, iH = Map.GetGridSize()
	for y = 0, iH - 1 do
		for x = 0, iW - 1 do
			local plot = Map.GetPlot(x, y)
			--[[ if plot:GetResourceType(-1) == self.sugar_ID then
				local featureType = plot:GetFeatureType();
				if featureType == FeatureTypes.FEATURE_JUNGLE then
					local plotType = plot:GetPlotType();
					if plotType ~= PlotTypes.PLOT_LAND then
						plot:SetPlotType(PlotTypes.PLOT_LAND, false, true)
					end
					plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1)
					plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, true)
					--
					--print("-"); print("Fixed a Sugar/Jungle at plot", x, y);
				end
			end --]]
			if plot:GetResourceType(-1) == self.gems_ID or plot:GetResourceType(-1) == self.dye_ID or plot:GetResourceType(-1) == self.spices_ID or plot:GetResourceType(-1) == self.silk_ID or plot:GetResourceType(-1) == self.sugar_ID or plot:GetResourceType(-1) == self.truffles_ID then
				local featureType = plot:GetFeatureType();
				if featureType == FeatureTypes.FEATURE_JUNGLE then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, true)
				end
			end
			if plot:GetResourceType(-1) == self.gold_ID then
				local terrainType = plot:GetTerrainType();
				local plotType = plot:GetPlotType();
				if plotType ~= PlotTypes.PLOT_HILLS and terrainType == TerrainTypes.TERRAIN_DESERT then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, true)
				end
			end
			if plot:GetResourceType(-1) == self.silver_ID then
				local terrainType = plot:GetTerrainType();
				local featureType = plot:GetFeatureType();
				if plotType ~= PlotTypes.PLOT_HILLS then
					if terrainType == TerrainTypes.TERRAIN_GRASS then
						plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1)
					elseif terrainType == TerrainTypes.TERRAIN_TUNDRA then
						plot:SetPlotType(PlotTypes.PLOT_HILLS, false, true)
					end
				end
			end
			if plot:GetResourceType(-1) == self.fur_ID then
				local terrainType = plot:GetTerrainType();
				if terrainType == TerrainTypes.TERRAIN_TUNDRA then
					plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1)
				end
			end
			if plot:GetResourceType(-1) == self.dye_ID or plot:GetResourceType(-1) == self.spices_ID or plot:GetResourceType(-1) == self.sugar_ID then
				local featureType = plot:GetFeatureType();
				if featureType == FeatureTypes.FEATURE_MARSH then
					plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1)
				end
			end
			if plot:GetResourceType(-1) == self.dye_ID then
				local terrainType = plot:GetTerrainType();
				if terrainType == TerrainTypes.TERRAIN_TUNDRA then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, true)
				end
			end
			--[[if plot:GetResourceType(-1) == self.gold_ID or plot:GetResourceType(-1) == self.copper_ID or plot:GetResourceType(-1) == self.silver_ID or plot:GetResourceType(-1) == self.gems_ID then
				local plotType = plot:GetPlotType();
				if plotType ~= PlotTypes.PLOT_HILLS then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, true)
				end
			end
			if plot:GetResourceType(-1) == self.marble_ID then
				local terrainType = plot:GetTerrainType();
				local plotType = plot:GetPlotType();
				if terrainType == PlotTypes.TERRAIN_DESERT and plotType ~= PlotTypes.PLOT_HILLS then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, true)
				end
			end--]]
		end
	end
end
------------------------------------------------------------------------------
function AssignStartingPlots:AssignLuxuryToRegion(region_number)
	-- Assigns a luxury type to an individual region.
	local region_type = self.regionTypes[region_number];
	local luxury_candidates;
	if region_type > 0 and region_type < 9 then -- Note: if number of Region Types is modified, this line and the table to which it refers need adjustment.
		luxury_candidates = self.luxury_region_weights[region_type];
	else
		luxury_candidates = self.luxury_fallback_weights; -- Undefined Region, enable all possible luxury types.
	end
	--
	-- Build options list.
	local iNumAvailableTypes = 0;
	local resource_IDs, resource_weights, res_threshold = {}, {}, {};
	local split_cap = self:GetLuxuriesSplitCap() -- New for expansion. Cap no longer set to hardcoded value of 3.
	
	for index, resource_options in ipairs(luxury_candidates) do
		local res_ID = resource_options[1];
		if self.luxury_assignment_count[res_ID] < split_cap then -- This type still eligible.
			local test = TestMembership(self.resourceIDs_assigned_to_regions, res_ID)
			if self.iNumTypesAssignedToRegions < self.iNumMaxAllowedForRegions or test == true then -- Not a new type that would exceed number of allowed types, so continue.
				-- Water-based resources need to run a series of permission checks: coastal start in region, not a disallowed regions type, enough water, etc.
				if res_ID == self.whale_ID or res_ID == self.pearls_ID or res_ID == self.crab_ID then
					if res_ID == self.whale_ID and self.regionTypes[region_number] == 2 then
						-- No whales in jungle regions, sorry
					elseif res_ID == self.pearls_ID and self.regionTypes[region_number] == 1 then
						-- No pearls in tundra regions, sorry
					elseif res_ID == self.crab_ID and self.regionTypes[region_number] == 4 then
						-- No crabs in desert regions, sorry					
					else
						if self.startLocationConditions[region_number][1] == true then -- This region's start is along an ocean, so water-based luxuries are allowed.
							if self.regionTerrainCounts[region_number][8] >= 12 then -- Enough water available.
								table.insert(resource_IDs, res_ID);
								local adjusted_weight = resource_options[2] / (1 + self.luxury_assignment_count[res_ID]) -- If selected before, for a different region, reduce weight.
								table.insert(resource_weights, adjusted_weight);
								iNumAvailableTypes = iNumAvailableTypes + 1;
							end
						end
					end
				-- Land-based resources are automatically approved if they were in the region's option table.
				elseif res_ID == self.salt_ID  or res_ID == self.marble_ID then
					-- No salt to regions please, sorry
				else
					table.insert(resource_IDs, res_ID);
					local adjusted_weight = resource_options[2] / (1 + self.luxury_assignment_count[res_ID])
					table.insert(resource_weights, adjusted_weight);
					iNumAvailableTypes = iNumAvailableTypes + 1;
				end
			end
		end
	end
	
	-- If options list is empty, pick from fallback options. First try to respect water-resources not being assigned to regions without coastal starts.
	if iNumAvailableTypes == 0 then
		for index, resource_options in ipairs(self.luxury_fallback_weights) do
			local res_ID = resource_options[1];
			if self.luxury_assignment_count[res_ID] < 3 then -- This type still eligible.
				local test = TestMembership(self.resourceIDs_assigned_to_regions, res_ID)
				if self.iNumTypesAssignedToRegions < self.iNumMaxAllowedForRegions or test == true then -- Won't exceed allowed types.
					if res_ID == self.whale_ID or res_ID == self.pearls_ID then
						if res_ID == self.whale_ID and self.regionTypes[region_number] == 2 then
							-- No whales in jungle regions, sorry
						elseif res_ID == self.pearls_ID and self.regionTypes[region_number] == 1 then
							-- No pearls in tundra regions, sorry
						else
							if self.startLocationConditions[region_number][1] == true then -- This region's start is along an ocean, so water-based luxuries are allowed.
								if self.regionTerrainCounts[region_number][8] >= 12 then -- Enough water available.
									table.insert(resource_IDs, res_ID);
									local adjusted_weight = resource_options[2] / (1 + self.luxury_assignment_count[res_ID]) -- If selected before, for a different region, reduce weight.
									table.insert(resource_weights, adjusted_weight);
									iNumAvailableTypes = iNumAvailableTypes + 1;
								end
							end
						end
					elseif res_ID == self.salt_ID or res_ID == self.marble_ID then
					-- No salt to regions please, sorry
					else
						table.insert(resource_IDs, res_ID);
						local adjusted_weight = resource_options[2] / (1 + self.luxury_assignment_count[res_ID])
						table.insert(resource_weights, adjusted_weight);
						iNumAvailableTypes = iNumAvailableTypes + 1;
					end
				end
			end
		end
	end

	-- If we get to here and still need to assign a luxury type, it means we have to force a water-based luxury in to this region, period.
	-- This should be the rarest of the rare emergency assignment cases, unless modifications to the system have tightened things too far.
	if iNumAvailableTypes == 0 then
		print("-"); print("Having to use emergency Luxury assignment process for Region#", region_number);
		print("This likely means a near-maximum number of civs in this game, and problems with not having enough legal Luxury types to spread around.");
		print("If you are modifying luxury types or number of regions allowed to get the same type, check to make sure your changes haven't violated the math so each region can have a legal assignment.");
		for index, resource_options in ipairs(self.luxury_fallback_weights) do
			local res_ID = resource_options[1];
			if self.luxury_assignment_count[res_ID] < 3 then -- This type still eligible.
				local test = TestMembership(self.resourceIDs_assigned_to_regions, res_ID)
				if self.iNumTypesAssignedToRegions < self.iNumMaxAllowedForRegions or test == true then -- Won't exceed allowed types.
					table.insert(resource_IDs, res_ID);
					local adjusted_weight = resource_options[2] / (1 + self.luxury_assignment_count[res_ID])
					table.insert(resource_weights, adjusted_weight);
					iNumAvailableTypes = iNumAvailableTypes + 1;
				end
			end
		end
	end
	if iNumAvailableTypes == 0 then -- Bad mojo!
		print("-"); print("FAILED to assign a Luxury type to Region#", region_number); print("-");
	end

	-- Choose luxury.
	local totalWeight = 0;
	for i, this_weight in ipairs(resource_weights) do
		totalWeight = totalWeight + this_weight;
	end
	local accumulatedWeight = 0;
	for index = 1, iNumAvailableTypes do
		local threshold = (resource_weights[index] + accumulatedWeight) * 10000 / totalWeight;
		table.insert(res_threshold, threshold);
		accumulatedWeight = accumulatedWeight + resource_weights[index];
	end
	local use_this_ID;
	local diceroll = Map.Rand(10000, "Choose resource type - Assign Luxury To Region - Lua");
	for index, threshold in ipairs(res_threshold) do
		if diceroll <= threshold then -- Choose this resource type.
			use_this_ID = resource_IDs[index];
			break
		end
	end
	
	return use_this_ID;
end
------------------------------------------------------------------------------
function AssignStartingPlots:NormalizeStartLocation(region_number)
	--[[ This function measures the value of land in two rings around a given start
	     location, primarily for the purpose of determining how much support the site
	     requires in the form of Bonus Resources. Numerous assumptions are built in 
	     to this operation that would need to be adjusted for any modifications to 
	     terrain or resources types and yields, or to game rules about rivers and 
	     other map elements. Nothing is hardcoded in a way that puts it out of the 
	     reach of modders, but any mods including changes to map elements may have a
	     significant workload involved with rebalancing the start finder and the 
	     resource distribution to fit them properly to a mod's custom needs. I have
	     labored to document every function and method in detail to make it as easy
	     as possible to modify this system.  -- Bob Thomas - April 15, 2010  ]]--
	-- 
	local iW, iH = Map.GetGridSize();
	local start_point_data = self.startingPlots[region_number];
	local x = start_point_data[1];
	local y = start_point_data[2];
	local plot = Map.GetPlot(x, y);
	local plotIndex = y * iW + x + 1;
	local isEvenY = true;
	if y / 2 > math.floor(y / 2) then
		isEvenY = false;
	end
	local wrapX = Map:IsWrapX();
	local wrapY = Map:IsWrapY();
	local innerFourFood, innerThreeFood, innerTwoFood, innerHills, innerForest, innerOneHammer, innerOcean = 0, 0, 0, 0, 0, 0, 0;
	local outerFourFood, outerThreeFood, outerTwoFood, outerHills, outerForest, outerOneHammer, outerOcean = 0, 0, 0, 0, 0, 0, 0;
	local innerCanHaveBonus, outerCanHaveBonus, innerBadTiles, outerBadTiles = 0, 0, 0, 0;
	local iNumFoodBonusNeeded = 0;
	local iNumNativeTwoFoodFirstRing, iNumNativeTwoFoodSecondRing = 0, 0; -- Cities must begin the game with at least three native 2F tiles, one in first ring.
	local search_table = {};
	
	-- Remove any feature Ice from the first ring.
	self:GenerateLuxuryPlotListsAtCitySite(x, y, 1, true)
	
	-- Set up Conditions checks.
	local alongOcean = false;
	local nextToLake = false;
	local isRiver = false;
	local nearRiver = false;
	local nearMountain = false;
	local forestCount, jungleCount = 0, 0;
	local res = Map.GetCustomOption(5);
	local start = Map.GetCustomOption(7);

	-- Check start plot to see if it's adjacent to saltwater.
	if self.plotDataIsCoastal[plotIndex] == true then
		alongOcean = true;
	end
	
	-- Check start plot to see if it's on a river.
	if plot:IsRiver() then
		isRiver = true;
	end

	-- Data Chart for early game tile potentials
	--
	-- 4F:	Flood Plains, Grass on fresh water (includes forest and marsh).
	-- 3F:	Dry Grass, Plains on fresh water (includes forest and jungle), Tundra on fresh water (includes forest), Oasis
	-- 2F:  Dry Plains, Lake, all remaining Jungles.
	--
	-- 1H:	Plains, Jungle on Plains

	-- Adding evaluation of grassland and plains for balance boost of bonus Cows for heavy grass starts. -1/26/2011 BT
	local iNumGrass, iNumPlains = 0, 0;

	-- Evaluate First Ring
	if isEvenY then
		search_table = self.firstRingYIsEven;
	else
		search_table = self.firstRingYIsOdd;
	end

	for loop, plot_adjustments in ipairs(search_table) do
		local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
		--
		if searchX < 0 or searchX >= iW or searchY < 0 or searchY >= iH then
			-- This plot does not exist. It's off the map edge.
			innerBadTiles = innerBadTiles + 1;
		else
			local searchPlot = Map.GetPlot(searchX, searchY)
			local plotType = searchPlot:GetPlotType()
			local terrainType = searchPlot:GetTerrainType()
			local featureType = searchPlot:GetFeatureType()
			--
			if plotType == PlotTypes.PLOT_MOUNTAIN then
				local nearMountain = true;
				innerBadTiles = innerBadTiles + 1;
			elseif plotType == PlotTypes.PLOT_OCEAN then
				if searchPlot:IsLake() then
					nextToLake = true;
					if featureType == FeatureTypes.FEATURE_ICE then
						innerBadTiles = innerBadTiles + 1;
					else
						innerTwoFood = innerTwoFood + 1;
						iNumNativeTwoFoodFirstRing = iNumNativeTwoFoodFirstRing + 1;
					end
				else
					if featureType == FeatureTypes.FEATURE_ICE then
						innerBadTiles = innerBadTiles + 1;
					else
						innerOcean = innerOcean + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1;
					end
				end
			else -- Habitable plot.
				if featureType == FeatureTypes.FEATURE_JUNGLE then
					jungleCount = jungleCount + 1;
					iNumNativeTwoFoodFirstRing = iNumNativeTwoFoodFirstRing + 1;
				elseif featureType == FeatureTypes.FEATURE_FOREST then
					forestCount = forestCount + 1;
				end
				if searchPlot:IsRiver() then
					nearRiver = true;
				end
				if plotType == PlotTypes.PLOT_HILLS then
					innerHills = innerHills + 1;
					if featureType == FeatureTypes.FEATURE_JUNGLE then
						--innerTwoFood = innerTwoFood + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1;
					elseif featureType == FeatureTypes.FEATURE_FOREST then
						innerCanHaveBonus = innerCanHaveBonus + 1;
					elseif terrainType == TerrainTypes.TERRAIN_GRASS then
						iNumGrass = iNumGrass + 1;
					elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
						iNumPlains = iNumPlains + 1;
					end
				elseif featureType == FeatureTypes.FEATURE_OASIS then
					innerThreeFood = innerThreeFood + 1;
					iNumNativeTwoFoodFirstRing = iNumNativeTwoFoodFirstRing + 1;
				elseif searchPlot:IsFreshWater() then
					if terrainType == TerrainTypes.TERRAIN_GRASS then
						innerFourFood = innerFourFood + 1;
						iNumGrass = iNumGrass + 1;
						if featureType ~= FeatureTypes.FEATURE_MARSH then
							innerCanHaveBonus = innerCanHaveBonus + 1;
						end
						if featureType == FeatureTypes.FEATURE_FOREST then
							innerForest = innerForest + 1;
						end
						if featureType == FeatureTypes.NO_FEATURE then
							iNumNativeTwoFoodFirstRing = iNumNativeTwoFoodFirstRing + 1;
						end
					elseif featureType == FeatureTypes.FEATURE_FLOOD_PLAINS then
						innerFourFood = innerFourFood + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1;
						iNumNativeTwoFoodFirstRing = iNumNativeTwoFoodFirstRing + 1;
					elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
						innerThreeFood = innerThreeFood + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1;
						iNumPlains = iNumPlains + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							innerForest = innerForest + 1;
						else
							innerOneHammer = innerOneHammer + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_TUNDRA then
						--innerThreeFood = innerThreeFood + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							innerForest = innerForest + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_DESERT then
						innerBadTiles = innerBadTiles + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1; -- Can have Oasis.
					else -- Snow
						innerBadTiles = innerBadTiles + 1;
					end
				else -- Dry Flatlands
					if terrainType == TerrainTypes.TERRAIN_GRASS then
						innerThreeFood = innerThreeFood + 1;
						iNumGrass = iNumGrass + 1;
						if featureType ~= FeatureTypes.FEATURE_MARSH then
							innerCanHaveBonus = innerCanHaveBonus + 1;
						end
						if featureType == FeatureTypes.FEATURE_FOREST then
							innerForest = innerForest + 1;
						end
						if featureType == FeatureTypes.NO_FEATURE then
							iNumNativeTwoFoodFirstRing = iNumNativeTwoFoodFirstRing + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
						innerTwoFood = innerTwoFood + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1;
						iNumPlains = iNumPlains + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							innerForest = innerForest + 1;
						else
							innerOneHammer = innerOneHammer + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_TUNDRA then
						innerCanHaveBonus = innerCanHaveBonus + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							innerForest = innerForest + 1;
						else
							innerBadTiles = innerBadTiles + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_DESERT then
						innerBadTiles = innerBadTiles + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1; -- Can have Oasis.
					else -- Snow
						innerBadTiles = innerBadTiles + 1;
					end
				end
			end
		end
	end
				
	-- Evaluate Second Ring
	if isEvenY then
		search_table = self.secondRingYIsEven;
	else
		search_table = self.secondRingYIsOdd;
	end

	for loop, plot_adjustments in ipairs(search_table) do
		local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
		local plot = Map.GetPlot(x, y);
		--
		--
		if searchX < 0 or searchX >= iW or searchY < 0 or searchY >= iH then
			-- This plot does not exist. It's off the map edge.
			outerBadTiles = outerBadTiles + 1;
		else
			local searchPlot = Map.GetPlot(searchX, searchY)
			local plotType = searchPlot:GetPlotType()
			local terrainType = searchPlot:GetTerrainType()
			local featureType = searchPlot:GetFeatureType()
			--
			if plotType == PlotTypes.PLOT_MOUNTAIN then
				local nearMountain = true;
				outerBadTiles = outerBadTiles + 1;
			elseif plotType == PlotTypes.PLOT_OCEAN then
				if searchPlot:IsLake() then
					if featureType == FeatureTypes.FEATURE_ICE then
						outerBadTiles = outerBadTiles + 1;
					else
						outerTwoFood = outerTwoFood + 1;
						iNumNativeTwoFoodSecondRing = iNumNativeTwoFoodSecondRing + 1;
					end
				else
					if featureType == FeatureTypes.FEATURE_ICE then
						outerBadTiles = outerBadTiles + 1;
					elseif terrainType == TerrainTypes.TERRAIN_COAST then
						outerCanHaveBonus = outerCanHaveBonus + 1;
						outerOcean = outerOcean + 1;
					end
				end
			else -- Habitable plot.
				if featureType == FeatureTypes.FEATURE_JUNGLE then
					jungleCount = jungleCount + 1;
					iNumNativeTwoFoodSecondRing = iNumNativeTwoFoodSecondRing + 1;
				elseif featureType == FeatureTypes.FEATURE_FOREST then
					forestCount = forestCount + 1;
				end
				if searchPlot:IsRiver() then
					nearRiver = true;
				end
				if plotType == PlotTypes.PLOT_HILLS then
					outerHills = outerHills + 1;
					if featureType == FeatureTypes.FEATURE_JUNGLE then
						--outerTwoFood = outerTwoFood + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1;
					elseif featureType == FeatureTypes.FEATURE_FOREST then
						outerCanHaveBonus = outerCanHaveBonus + 1;
					elseif terrainType == TerrainTypes.TERRAIN_GRASS then
						iNumGrass = iNumGrass + 1;
					elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
						iNumPlains = iNumPlains + 1;
					end
				elseif featureType == FeatureTypes.FEATURE_OASIS then
					innerThreeFood = innerThreeFood + 1;
					iNumNativeTwoFoodSecondRing = iNumNativeTwoFoodSecondRing + 1;
				elseif searchPlot:IsFreshWater() then
					if terrainType == TerrainTypes.TERRAIN_GRASS then
						outerFourFood = outerFourFood + 1;
						iNumGrass = iNumGrass + 1;
						if featureType ~= FeatureTypes.FEATURE_MARSH then
							outerCanHaveBonus = outerCanHaveBonus + 1;
						end
						if featureType == FeatureTypes.FEATURE_FOREST then
							outerForest = outerForest + 1;
						end
						if featureType == FeatureTypes.NO_FEATURE then
							iNumNativeTwoFoodSecondRing = iNumNativeTwoFoodSecondRing + 1;
						end
					elseif featureType == FeatureTypes.FEATURE_FLOOD_PLAINS then
						outerFourFood = outerFourFood + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1;
						iNumNativeTwoFoodSecondRing = iNumNativeTwoFoodSecondRing + 1;
					elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
						outerThreeFood = outerThreeFood + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1;
						iNumPlains = iNumPlains + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							outerForest = outerForest + 1;
						else
							outerOneHammer = outerOneHammer + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_TUNDRA then
						--outerThreeFood = outerThreeFood + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							outerForest = outerForest + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_DESERT then
						outerBadTiles = outerBadTiles + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1; -- Can have Oasis.
					else -- Snow
						outerBadTiles = outerBadTiles + 1;
					end
				else -- Dry Flatlands
					if terrainType == TerrainTypes.TERRAIN_GRASS then
						outerThreeFood = outerThreeFood + 1;
						iNumGrass = iNumGrass + 1;
						if featureType ~= FeatureTypes.FEATURE_MARSH then
							outerCanHaveBonus = outerCanHaveBonus + 1;
						end
						if featureType == FeatureTypes.FEATURE_FOREST then
							outerForest = outerForest + 1;
						end
						if featureType == FeatureTypes.NO_FEATURE then
							iNumNativeTwoFoodSecondRing = iNumNativeTwoFoodSecondRing + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
						outerTwoFood = outerTwoFood + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1;
						iNumPlains = iNumPlains + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							outerForest = outerForest + 1;
						else
							outerOneHammer = outerOneHammer + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_TUNDRA then
						outerCanHaveBonus = outerCanHaveBonus + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							outerForest = outerForest + 1;
						else
							outerBadTiles = outerBadTiles + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_DESERT then
						outerBadTiles = outerBadTiles + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1; -- Can have Oasis.
					else -- Snow
						outerBadTiles = outerBadTiles + 1;
					end
				end
			end
		end
	end
	
	-- Adjust the hammer situation, if needed.
	local innerHammerScore = (4 * innerHills) + (2 * innerForest) + innerOneHammer;
	local outerHammerScore = (2 * outerHills) + outerForest + outerOneHammer;
	local earlyHammerScore = (2 * innerForest) + outerForest + innerOneHammer + outerOneHammer;
	-- If drastic shortage, attempt to add a hill to first ring.
	if (outerHammerScore <= 10 and innerHammerScore <= 4) or innerHammerScore == 0 then -- Change a first ring plot to Hills.
		if isEvenY then
			randomized_first_ring_adjustments = GetShuffledCopyOfTable(self.firstRingYIsEven);
		else
			randomized_first_ring_adjustments = GetShuffledCopyOfTable(self.firstRingYIsOdd);
		end
		for attempt = 1, 6 do
			local plot_adjustments = randomized_first_ring_adjustments[attempt];
			local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
			-- Attempt to place a Hill at the currently chosen plot.
			local placedHill = self:AttemptToPlaceHillsAtPlot(searchX, searchY);
			if placedHill == true then
				innerHammerScore = innerHammerScore + 4;
				--print("Added hills next to hammer-poor start plot at ", x, y);
				break
			elseif attempt == 6 then
				--print("FAILED to add hills next to hammer-poor start plot at ", x, y);
			end
		end
	end
	
	-- Add mandatory Iron, Horse, Oil to every start if Strategic Balance option is enabled.
	if res == 5 or res == 6 then
		self:AddStrategicBalanceResources(region_number)
	end
	
	-- If early hammers will be too short, attempt to add a small Horse or Iron to second ring.
	if innerHammerScore < 3 and earlyHammerScore < 6 then -- Add a small Horse or Iron to second ring.
		if isEvenY then
			randomized_second_ring_adjustments = GetShuffledCopyOfTable(self.secondRingYIsEven);
		else
			randomized_second_ring_adjustments = GetShuffledCopyOfTable(self.secondRingYIsOdd);
		end
		for attempt = 1, 12 do
			local plot_adjustments = randomized_second_ring_adjustments[attempt];
			local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
			-- Attempt to place a Hill at the currently chosen plot.
			local placedStrategic = self:AttemptToPlaceSmallStrategicAtPlot(searchX, searchY);
			if placedStrategic == true then
				break
			elseif attempt == 12 then
				--print("FAILED to add small strategic resource near hammer-poor start plot at ", x, y);
			end
		end
	end
	
	-- Rate the food situation.
	local innerFoodScore = (4 * innerFourFood) + (2 * innerThreeFood) + innerTwoFood;
	local outerFoodScore = (4 * outerFourFood) + (2 * outerThreeFood) + outerTwoFood;
	local totalFoodScore = innerFoodScore + outerFoodScore;
	local nativeTwoFoodTiles = iNumNativeTwoFoodFirstRing + iNumNativeTwoFoodSecondRing;

	--[[ Debug printout of food scores.
	print("-");
	print("-- - Start Point in Region #", region_number, " has Food Score of ", totalFoodScore, " with rings of ", innerFoodScore, outerFoodScore);
	]]--	
	
	-- Six levels for Bonus Resource support, from zero to five.
	if totalFoodScore < 4 and innerFoodScore == 0 then
		iNumFoodBonusNeeded = 5;
	elseif totalFoodScore < 6 then
		iNumFoodBonusNeeded = 4;
	elseif totalFoodScore < 8 then
		iNumFoodBonusNeeded = 3;
	elseif totalFoodScore < 12 and innerFoodScore < 5 then
		iNumFoodBonusNeeded = 3;
	elseif totalFoodScore < 17 and innerFoodScore < 9 then
		iNumFoodBonusNeeded = 2;
	elseif nativeTwoFoodTiles <= 1 then
		iNumFoodBonusNeeded = 2;
	elseif totalFoodScore < 24 and innerFoodScore < 11 then
		iNumFoodBonusNeeded = 1;
	elseif nativeTwoFoodTiles == 2 or iNumNativeTwoFoodFirstRing < 2 then
		iNumFoodBonusNeeded = 1;
	elseif totalFoodScore < 20 then
		iNumFoodBonusNeeded = 1;
	end
	
	-- Check for Legendary Start resource option.
	if res == 4 then
		iNumFoodBonusNeeded = iNumFoodBonusNeeded + 2;
	elseif (res == 5 or res == 6) and start == 1 then
		iNumFoodBonusNeeded = iNumFoodBonusNeeded + 1;
	end
	
	-- Check to see if a Grass tile needs to be added at an all-plains site with zero native 2-food tiles in first two rings.
	if nativeTwoFoodTiles == 0 and iNumFoodBonusNeeded < 3 then
		local odd = self.firstRingYIsOdd;
		local even = self.firstRingYIsEven;
		local plot_list = {};
		-- For notes on how the hex-iteration works, refer to PlaceResourceImpact()
		local ripple_radius = 2;
		local currentX = x - ripple_radius;
		local currentY = y;
		for direction_index = 1, 6 do
			for plot_to_handle = 1, ripple_radius do
			 	if currentY / 2 > math.floor(currentY / 2) then
					plot_adjustments = odd[direction_index];
				else
					plot_adjustments = even[direction_index];
				end
				nextX = currentX + plot_adjustments[1];
				nextY = currentY + plot_adjustments[2];
				if wrapX == false and (nextX < 0 or nextX >= iW) then
					-- X is out of bounds.
				elseif wrapY == false and (nextY < 0 or nextY >= iH) then
					-- Y is out of bounds.
				else
					local realX = nextX;
					local realY = nextY;
					if wrapX then
						realX = realX % iW;
					end
					if wrapY then
						realY = realY % iH;
					end
					-- We've arrived at the correct x and y for the current plot.
					local plot = Map.GetPlot(realX, realY);
					if plot:GetResourceType(-1) == -1 then -- No resource here, safe to proceed.
						local plotType = plot:GetPlotType()
						local terrainType = plot:GetTerrainType()
						local featureType = plot:GetFeatureType()
						local plotIndex = realY * iW + realX + 1;
						-- Now check this plot for eligibility to be converted to flat open grassland.
						if plotType == PlotTypes.PLOT_LAND then
							if terrainType == TerrainTypes.TERRAIN_PLAINS then
								if featureType == FeatureTypes.NO_FEATURE then
									table.insert(plot_list, plotIndex);
								end
							end
						end
					end
				end
				currentX, currentY = nextX, nextY;
			end
		end
		local iNumConversionCandidates = table.maxn(plot_list);
		if iNumConversionCandidates == 0 then
			iNumFoodBonusNeeded = 3;
		else
			--print("-"); print("*** START HAD NO 2-FOOD TILES, YET ONLY QUALIFIED FOR 2 BONUS; CONVERTING A PLAINS TO GRASS! ***"); print("-");
			local diceroll = 1 + Map.Rand(iNumConversionCandidates, "Choosing plot to convert to Grass near food-poor Plains start - LUA");
			local conversionPlotIndex = plot_list[diceroll];
			local conv_x = (conversionPlotIndex - 1) % iW;
			local conv_y = (conversionPlotIndex - conv_x - 1) / iW;
			local plot = Map.GetPlot(conv_x, conv_y);
			plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false)
			self:PlaceResourceImpact(conv_x, conv_y, 1, 0) -- Disallow strategic resources at this plot, to keep it a farm plot.
		end
	end
	-- Add Bonus Resources to food-poor start positions.
	if iNumFoodBonusNeeded > 0 then
		local maxBonusesPossible = innerCanHaveBonus + outerCanHaveBonus;

		--print("-");
		--print("Food-Poor start ", x, y, " needs ", iNumFoodBonusNeeded, " Bonus, with ", maxBonusesPossible, " eligible plots.");
		--print("-");

		local innerPlaced, outerPlaced = 0, 0;
		local randomized_first_ring_adjustments, randomized_second_ring_adjustments, randomized_third_ring_adjustments;
		if isEvenY then
			randomized_first_ring_adjustments = GetShuffledCopyOfTable(self.firstRingYIsEven);
			randomized_second_ring_adjustments = GetShuffledCopyOfTable(self.secondRingYIsEven);
			randomized_third_ring_adjustments = GetShuffledCopyOfTable(self.thirdRingYIsEven);
		else
			randomized_first_ring_adjustments = GetShuffledCopyOfTable(self.firstRingYIsOdd);
			randomized_second_ring_adjustments = GetShuffledCopyOfTable(self.secondRingYIsOdd);
			randomized_third_ring_adjustments = GetShuffledCopyOfTable(self.thirdRingYIsOdd);
		end
		local tried_all_first_ring = false;
		local tried_all_second_ring = false;
		local tried_all_third_ring = false;
		local allow_oasis = true; -- Permanent flag. (We don't want to place more than one Oasis per location).
		local placedOasis; -- Records returning result from each attempt.
		while iNumFoodBonusNeeded > 0 do
			if ((innerPlaced < 2 and innerCanHaveBonus > 0) or (res == 4 and innerPlaced < 3 and innerCanHaveBonus > 0))
			  and tried_all_first_ring == false then
				-- Add bonus to inner ring.
				for attempt = 1, 6 do
					local plot_adjustments = randomized_first_ring_adjustments[attempt];
					local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
					-- Attempt to place a Bonus at the currently chosen plot.
					local placedBonus, placedOasis = self:AttemptToPlaceBonusResourceAtPlot(searchX, searchY, allow_oasis);
					if placedBonus == true then
						if allow_oasis == true and placedOasis == true then -- First oasis was placed on this pass, so change permission.
							allow_oasis = false;
						end
						--print("Placed a Bonus in first ring at ", searchX, searchY);
						innerPlaced = innerPlaced + 1;
						innerCanHaveBonus = innerCanHaveBonus - 1;
						iNumFoodBonusNeeded = iNumFoodBonusNeeded - 1;
						break
					elseif attempt == 6 then
						tried_all_first_ring = true;
					end
				end

			elseif ((innerPlaced + outerPlaced < 5 and outerCanHaveBonus > 0) or (res == 4 and innerPlaced + outerPlaced < 4 and outerCanHaveBonus > 0))
			  and tried_all_second_ring == false then
				-- Add bonus to second ring.
				for attempt = 1, 12 do
					local plot_adjustments = randomized_second_ring_adjustments[attempt];
					local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
					-- Attempt to place a Bonus at the currently chosen plot.
					local placedBonus, placedOasis = self:AttemptToPlaceBonusResourceAtPlot(searchX, searchY, allow_oasis);
					if placedBonus == true then
						if allow_oasis == true and placedOasis == true then -- First oasis was placed on this pass, so change permission.
							allow_oasis = false;
						end
						--print("Placed a Bonus in second ring at ", searchX, searchY);
						outerPlaced = outerPlaced + 1;
						outerCanHaveBonus = outerCanHaveBonus - 1;
						iNumFoodBonusNeeded = iNumFoodBonusNeeded - 1;
						break
					elseif attempt == 12 then
						tried_all_second_ring = true;
					end
				end

			elseif tried_all_third_ring == false then
				-- Add bonus to third ring.
				for attempt = 1, 18 do
					local plot_adjustments = randomized_third_ring_adjustments[attempt];
					local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
					-- Attempt to place a Bonus at the currently chosen plot.
					local placedBonus, placedOasis = self:AttemptToPlaceBonusResourceAtPlot(searchX, searchY, allow_oasis);
					if placedBonus == true then
						if allow_oasis == true and placedOasis == true then -- First oasis was placed on this pass, so change permission.
							allow_oasis = false;
						end
						--print("Placed a Bonus in third ring at ", searchX, searchY);
						iNumFoodBonusNeeded = iNumFoodBonusNeeded - 1;
						break
					elseif attempt == 18 then
						tried_all_third_ring = true;
					end
				end
				
			else -- Tried everywhere, have to give up.
				break				
			end
		end
	end

	-- Check for heavy grass and light plains. Adding Stone if grass count is high and plains count is low. - May 2011, BT
	local iNumStoneNeeded = 0;
	if start == 1 then
		if iNumGrass >= 8 and iNumPlains - jungleCount <= 0 then
			iNumStoneNeeded = 2;
		elseif iNumGrass >= 5 and iNumPlains - jungleCount <= 4 then
			iNumStoneNeeded = 1;
		end
	else
		if iNumGrass >= 9 and iNumPlains == 0 then
			iNumStoneNeeded = 2;
		elseif iNumGrass >= 6 and iNumPlains <= 4 then
			iNumStoneNeeded = 1;
		end
	end
	if iNumStoneNeeded > 0 then -- Add Stone to this grass start.
		local stonePlaced, innerPlaced = 0, 0;
		local randomized_first_ring_adjustments, randomized_second_ring_adjustments;
		if isEvenY then
			randomized_first_ring_adjustments = GetShuffledCopyOfTable(self.firstRingYIsEven);
			randomized_second_ring_adjustments = GetShuffledCopyOfTable(self.secondRingYIsEven);
		else
			randomized_first_ring_adjustments = GetShuffledCopyOfTable(self.firstRingYIsOdd);
			randomized_second_ring_adjustments = GetShuffledCopyOfTable(self.secondRingYIsOdd);
		end
		local tried_all_first_ring = false;
		local tried_all_second_ring = false;
		while iNumStoneNeeded > 0 do
			if innerPlaced < 1 and tried_all_first_ring == false then
				-- Add bonus to inner ring.
				for attempt = 1, 6 do
					local plot_adjustments = randomized_first_ring_adjustments[attempt];
					local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
					-- Attempt to place Cows at the currently chosen plot.
					local placedBonus = self:AttemptToPlaceStoneAtGrassPlot(searchX, searchY);
					if placedBonus == true then
						--print("Placed Stone in first ring at ", searchX, searchY);
						innerPlaced = innerPlaced + 1;
						iNumStoneNeeded = iNumStoneNeeded - 1;
						break
					elseif attempt == 6 then
						tried_all_first_ring = true;
					end
				end

			elseif tried_all_second_ring == false then
				-- Add bonus to second ring.
				for attempt = 1, 12 do
					local plot_adjustments = randomized_second_ring_adjustments[attempt];
					local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
					-- Attempt to place Stone at the currently chosen plot.
					local placedBonus = self:AttemptToPlaceStoneAtGrassPlot(searchX, searchY);
					if placedBonus == true then
						--print("Placed Stone in second ring at ", searchX, searchY);
						iNumStoneNeeded = iNumStoneNeeded - 1;
						break
					elseif attempt == 12 then
						tried_all_second_ring = true;
					end
				end

			else -- Tried everywhere, have to give up.
				break				
			end
		end
	end
	
	-- Record conditions at this start location.
	local results_table = {alongOcean, nextToLake, isRiver, nearRiver, nearMountain, forestCount, jungleCount};
	self.startLocationConditions[region_number] = results_table;
end
------------------------------------------------------------------------------
function AssignStartingPlots:AddStrategicBalanceResources(region_number)
	-- This function adds the required Strategic Resources to start plots, for
	-- games that have selected to enable Strategic Resource Balance.
	local iW, iH = Map.GetGridSize();
	local start_point_data = self.startingPlots[region_number];
	local x = start_point_data[1];
	local y = start_point_data[2];
	local plot = Map.GetPlot(x, y);
	local plotIndex = y * iW + x + 1;
	local wrapX = Map:IsWrapX();
	local wrapY = Map:IsWrapY();
	local odd = self.firstRingYIsOdd;
	local even = self.firstRingYIsEven;
	local nextX, nextY, plot_adjustments;
	local iron_list, horse_list, oil_list, coal_list = {}, {}, {}, {};
	local iron_fallback, horse_fallback, oil_fallback, coal_fallback = {}, {}, {}, {};
	local radius = 3;
	local OilToPlace = 2;
	local res = Map.GetCustomOption(5);
	
	--print("- Adding Strategic Balance Resources for start location in Region#", region_number);
	
	for ripple_radius = 1, radius do
		local ripple_value = radius - ripple_radius + 1;
		local currentX = x - ripple_radius;
		local currentY = y;
		for direction_index = 1, 6 do
			for plot_to_handle = 1, ripple_radius do
			 	if currentY / 2 > math.floor(currentY / 2) then
					plot_adjustments = odd[direction_index];
				else
					plot_adjustments = even[direction_index];
				end
				nextX = currentX + plot_adjustments[1];
				nextY = currentY + plot_adjustments[2];
				if wrapX == false and (nextX < 0 or nextX >= iW) then
					-- X is out of bounds.
				elseif wrapY == false and (nextY < 0 or nextY >= iH) then
					-- Y is out of bounds.
				else
					local realX = nextX;
					local realY = nextY;
					if wrapX then
						realX = realX % iW;
					end
					if wrapY then
						realY = realY % iH;
					end
					-- We've arrived at the correct x and y for the current plot.
					local plot = Map.GetPlot(realX, realY);
					local plotType = plot:GetPlotType()
					local terrainType = plot:GetTerrainType()
					local featureType = plot:GetFeatureType()
					local plotIndex = realY * iW + realX + 1;
					-- Check this plot for resource placement eligibility.
					if plotType == PlotTypes.PLOT_HILLS then
						if ripple_radius < 3 then
							table.insert(iron_list, plotIndex)

						else
							table.insert(iron_fallback, plotIndex)

						end
						if terrainType ~= TerrainTypes.TERRAIN_SNOW and featureType == FeatureTypes.NO_FEATURE then
							table.insert(horse_fallback, plotIndex)
						end
					elseif plotType == PlotTypes.PLOT_LAND then
						if featureType == FeatureTypes.NO_FEATURE then
							if terrainType == TerrainTypes.TERRAIN_TUNDRA or terrainType == TerrainTypes.TERRAIN_DESERT then
								if ripple_radius < 3 then
									table.insert(oil_list, plotIndex)
								else
									table.insert(oil_fallback, plotIndex)
								end
								table.insert(iron_fallback, plotIndex)
								table.insert(horse_fallback, plotIndex)
							elseif terrainType == TerrainTypes.TERRAIN_PLAINS or terrainType == TerrainTypes.TERRAIN_GRASS then
								if ripple_radius < 3 then
									table.insert(horse_list, plotIndex)
								else
									table.insert(horse_fallback, plotIndex)
								end
								table.insert(iron_fallback, plotIndex)
								table.insert(oil_fallback, plotIndex)
							elseif terrainType == TerrainTypes.TERRAIN_SNOW then
								if ripple_radius < 3 then
									table.insert(oil_list, plotIndex)
								else
									table.insert(oil_fallback, plotIndex)
								end
							end
						elseif featureType == FeatureTypes.FEATURE_MARSH then		
							if ripple_radius < 3 then
								table.insert(oil_list, plotIndex)
							else
								table.insert(oil_fallback, plotIndex)
							end
							table.insert(iron_fallback, plotIndex)
						elseif featureType == FeatureTypes.FEATURE_FLOOD_PLAINS then		
							table.insert(horse_fallback, plotIndex)
							table.insert(oil_fallback, plotIndex)
						elseif featureType == FeatureTypes.FEATURE_JUNGLE or featureType == FeatureTypes.FEATURE_FOREST then		
							table.insert(iron_fallback, plotIndex)
							table.insert(oil_fallback, plotIndex)
						end
					end
					currentX, currentY = nextX, nextY;
				end
			end
		end
	end

	if res == 6 then
		local radius = 6;
		for ripple_radius = 1, radius do
			local ripple_value = radius - ripple_radius + 1;
			local currentX = x - ripple_radius;
			local currentY = y;
			for direction_index = 1, 6 do
				for plot_to_handle = 1, ripple_radius do
			 		if currentY / 2 > math.floor(currentY / 2) then
						plot_adjustments = odd[direction_index];
					else
						plot_adjustments = even[direction_index];
					end
					nextX = currentX + plot_adjustments[1];
					nextY = currentY + plot_adjustments[2];
					if wrapX == false and (nextX < 0 or nextX >= iW) then
						-- X is out of bounds.
					elseif wrapY == false and (nextY < 0 or nextY >= iH) then
						-- Y is out of bounds.
					else
						local realX = nextX;
						local realY = nextY;
						if wrapX then
							realX = realX % iW;
						end
						if wrapY then
							realY = realY % iH;
						end
						-- We've arrived at the correct x and y for the current plot.
						local plot = Map.GetPlot(realX, realY);
						local plotType = plot:GetPlotType()
						local terrainType = plot:GetTerrainType()
						local featureType = plot:GetFeatureType()
						local plotIndex = realY * iW + realX + 1;
						-- Check this plot for resource placement eligibility.
						if plotType == PlotTypes.PLOT_HILLS then
							if ripple_radius < 6 then
								table.insert(coal_list, plotIndex)
							else
								table.insert(coal_fallback, plotIndex)
							end
							if terrainType ~= TerrainTypes.TERRAIN_SNOW and featureType == FeatureTypes.NO_FEATURE then
								table.insert(horse_fallback, plotIndex)
							end
						elseif plotType == PlotTypes.PLOT_LAND then
							if featureType == FeatureTypes.NO_FEATURE then
								if terrainType == TerrainTypes.TERRAIN_TUNDRA or terrainType == TerrainTypes.TERRAIN_DESERT then
									if ripple_radius < 6 then
										table.insert(coal_list, plotIndex)
										table.insert(oil_fallback, plotIndex)
									else
										table.insert(coal_fallback, plotIndex)
									end
								elseif terrainType == TerrainTypes.TERRAIN_PLAINS or terrainType == TerrainTypes.TERRAIN_GRASS then
									if ripple_radius < 6 then
										table.insert(coal_list, plotIndex)
										table.insert(oil_fallback, plotIndex)
									else
										table.insert(coal_fallback, plotIndex)
									end
								elseif terrainType == TerrainTypes.TERRAIN_SNOW then
									if ripple_radius < 6 then
										table.insert(coal_list, plotIndex)
										table.insert(oil_fallback, plotIndex)
									else
										table.insert(coal_fallback, plotIndex)
									end
								end
							elseif featureType == FeatureTypes.FEATURE_MARSH then		
								if ripple_radius < 4 then
									table.insert(coal_list, plotIndex)
									table.insert(oil_fallback, plotIndex)
								else
									table.insert(coal_fallback, plotIndex)
								end
							elseif featureType == FeatureTypes.FEATURE_FLOOD_PLAINS then
								table.insert(coal_fallback, plotIndex)
							elseif featureType == FeatureTypes.FEATURE_JUNGLE or featureType == FeatureTypes.FEATURE_FOREST then
								table.insert(coal_fallback, plotIndex)
								table.insert(oil_fallback, plotIndex)
							end
						end
						currentX, currentY = nextX, nextY;
					end
				end
			end
		end
	end

	local uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = self:GetMajorStrategicResourceQuantityValues()
	coal_amt = 3;
	local shuf_list;
	local placed_iron, placed_horse, placed_oil, placed_coal = false, false, false, false;

	if table.maxn(iron_list) > 0 then
		shuf_list = GetShuffledCopyOfTable(iron_list)
		iNumLeftToPlace = self:PlaceSpecificNumberOfResources(self.iron_ID, iron_amt, 1, 1, -1, 0, 0, shuf_list);
		if iNumLeftToPlace == 0 then
			placed_iron = true;
		end
	end
	if table.maxn(horse_list) > 0 then
		shuf_list = GetShuffledCopyOfTable(horse_list)
		iNumLeftToPlace = self:PlaceSpecificNumberOfResources(self.horse_ID, horse_amt, 1, 1, -1, 0, 0, shuf_list);
		if iNumLeftToPlace == 0 then
			placed_horse = true;
		end
	end
	if table.maxn(oil_list) > 0 then
		shuf_list = GetShuffledCopyOfTable(oil_list)
		iNumLeftToPlace = self:PlaceSpecificNumberOfResources(self.oil_ID, oil_amt, 1, 1, -1, 0, 0, shuf_list);
		if iNumLeftToPlace == 0 then
			placed_oil = true;
		end
	end
	
	if res == 6 then
		if table.maxn(coal_list) > 0 then
			shuf_list = GetShuffledCopyOfTable(coal_list)
			iNumLeftToPlace = self:PlaceSpecificNumberOfResources(self.coal_ID, coal_amt, 1, 1, 1, 0, 0, shuf_list);
			if iNumLeftToPlace == 0 then
				placed_coal = true;
			end
		end
	end



	if placed_iron == false and table.maxn(iron_fallback) > 0 then
		shuf_list = GetShuffledCopyOfTable(iron_fallback)
		iNumLeftToPlace = self:PlaceSpecificNumberOfResources(self.iron_ID, iron_amt, 1, 1, -1, 0, 0, shuf_list);
	end
	if placed_horse == false and table.maxn(horse_fallback) > 0 then
		shuf_list = GetShuffledCopyOfTable(horse_fallback)
		iNumLeftToPlace = self:PlaceSpecificNumberOfResources(self.horse_ID, horse_amt, 1, 1, -1, 0, 0, shuf_list);
	end
	if placed_oil == false and table.maxn(oil_fallback) > 0 then
		shuf_list = GetShuffledCopyOfTable(oil_fallback)
		if OilToPlace == 1 then
			iNumLeftToPlace = self:PlaceSpecificNumberOfResources(self.oil_ID, oil_amt, 1, 1, -1, 0, 0, shuf_list);
		else
			iNumLeftToPlace = self:PlaceSpecificNumberOfResources(self.oil_ID, oil_amt, 2, 1, -1, 0, 0, shuf_list);
		end
		print("Fallback Used");
		if iNumLeftToPlace == 0 then
			print("All Oil Placed 2nd Attempt");
		else
			--print("Not All Oil Placed");
		end
	end
	if res == 6 then
		if placed_coal == false and table.maxn(coal_fallback) > 0 then
			shuf_list = GetShuffledCopyOfTable(coal_fallback)
			iNumLeftToPlace = self:PlaceSpecificNumberOfResources(self.coal_ID, coal_amt, 1, 1, 1, 0, 0, shuf_list);
		end
	end
end
------------------------------------------------------------------------------
function AssignStartingPlots:GenerateRegions(args)
	print("Map Generation - Dividing the map in to Regions");
	-- This function stores its data in the instance (self) data table.
	--
	-- The "Three Methods" of regional division:
	-- 1. Biggest Landmass: All civs start on the biggest landmass.
	-- 2. Continental: Civs are assigned to continents. Any continents with more than one civ are divided.
	-- 3. Rectangular: Civs start within a given rectangle that spans the whole map, without regard to landmass sizes.
	--                 This method is primarily applied to Archipelago and other maps with lots of tiny islands.
	-- 4. Rectangular: Civs start within a given rectangle defined by arguments passed in on the function call.
	--                 Arguments required for this method: iWestX, iSouthY, iWidth, iHeight
	local args = args or {};
	local iW, iH = Map.GetGridSize();
	self.method = args.method or self.method; -- Continental method is default.
	--self.resource_setting = args.resources or 2; -- Each map script has to pass in parameter for Resource setting chosen by user.
	local res = Map.GetCustomOption(5);
	self.resource_setting = res;

	-- Determine number of civilizations and city states present in this game.
	self.iNumCivs, self.iNumCityStates, self.player_ID_list, self.bTeamGame, self.teams_with_major_civs, self.number_civs_per_team = GetPlayerAndTeamInfo()
	self.iNumCityStatesUnassigned = self.iNumCityStates;
	print("-"); print("Civs:", self.iNumCivs); print("City States:", self.iNumCityStates);

	if self.method == 1 then -- Biggest Landmass
		-- Identify the biggest landmass.
		local biggest_area = Map.FindBiggestArea(False);
		local iAreaID = biggest_area:GetID();
		-- We'll need all eight data fields returned in the results table from the boundary finder:
		local landmass_data = ObtainLandmassBoundaries(iAreaID);
		local iWestX = landmass_data[1];
		local iSouthY = landmass_data[2];
		local iEastX = landmass_data[3];
		local iNorthY = landmass_data[4];
		local iWidth = landmass_data[5];
		local iHeight = landmass_data[6];
		local wrapsX = landmass_data[7];
		local wrapsY = landmass_data[8];
		
		-- Obtain "Start Placement Fertility" of the landmass. (This measurement is customized for start placement).
		-- This call returns a table recording fertility of all plots within a rectangle that contains the landmass,
		-- with a zero value for any plots not part of the landmass -- plus a fertility sum and plot count.
		local fert_table, fertCount, plotCount = self:MeasureStartPlacementFertilityOfLandmass(iAreaID, 
		                                         iWestX, iEastX, iSouthY, iNorthY, wrapsX, wrapsY);
		-- Now divide this landmass in to regions, one per civ.
		-- The regional divider requires three arguments:
		-- 1. Number of divisions. (For "Biggest Landmass" this means number of civs in the game).
		-- 2. Fertility table. (This was obtained from the last call.)
		-- 3. Rectangle table. This table includes seven data fields:
		-- westX, southY, width, height, AreaID, fertilityCount, plotCount
		-- This is why we got the fertCount and plotCount from the fertility function.
		--
		-- Assemble the Rectangle data table:
		local rect_table = {iWestX, iSouthY, iWidth, iHeight, iAreaID, fertCount, plotCount};
		-- The data from this call is processed in to self.regionData during the process.
		self:DivideIntoRegions(self.iNumCivs, fert_table, rect_table)
		-- The regions have been defined.
	
	elseif self.method == 3 or self.method == 4 then -- Rectangular
		-- Obtain the boundaries of the rectangle to be processed.
		-- If no coords were passed via the args table, default to processing the entire map.
		-- Note that it matters if method 3 or 4 is designated, because the difference affects
		-- how city states are placed, whether they look for any uninhabited lands outside the rectangle.
		self.inhabited_WestX = args.iWestX or 0;
		self.inhabited_SouthY = args.iSouthY or 0;
		self.inhabited_Width = args.iWidth or iW;
		self.inhabited_Height = args.iHeight or iH;

		-- Obtain "Start Placement Fertility" inside the rectangle.
		-- Data returned is: fertility table, sum of all fertility, plot count.
		local fert_table, fertCount, plotCount = self:MeasureStartPlacementFertilityInRectangle(self.inhabited_WestX, 
		                                         self.inhabited_SouthY, self.inhabited_Width, self.inhabited_Height)
		-- Assemble the Rectangle data table:
		local rect_table = {self.inhabited_WestX, self.inhabited_SouthY, self.inhabited_Width, 
		                    self.inhabited_Height, -1, fertCount, plotCount}; -- AreaID -1 means ignore area IDs.
		-- Divide the rectangle.
		self:DivideIntoRegions(self.iNumCivs, fert_table, rect_table)
		-- The regions have been defined.
	
	else -- Continental.
		--[[ Loop through all plots on the map, measuring fertility of each land 
		     plot, identifying its AreaID, building a list of landmass AreaIDs, and
		     tallying the Start Placement Fertility for each landmass. ]]--

		-- region_data: [WestX, EastX, SouthY, NorthY, 
		-- numLandPlotsinRegion, numCoastalPlotsinRegion,
		-- numOceanPlotsinRegion, iRegionNetYield, 
		-- iNumLandAreas, iNumPlotsinRegion]
		local best_areas = {};
		local globalFertilityOfLands = {};

		-- Obtain info on all landmasses for comparision purposes.
		local iGlobalFertilityOfLands = 0;
		local iNumLandPlots = 0;
		local iNumLandAreas = 0;
		local land_area_IDs = {};
		local land_area_plots = {};
		local land_area_fert = {};
		-- Cycle through all plots in the world, checking their Start Placement Fertility and AreaID.
		for x = 0, iW - 1 do
			for y = 0, iH - 1 do
				local i = y * iW + x + 1;
				local plot = Map.GetPlot(x, y);
				if not plot:IsWater() then -- Land plot, process it.
					iNumLandPlots = iNumLandPlots + 1;
					local iArea = plot:GetArea();
					local plotFertility = self:MeasureStartPlacementFertilityOfPlot(x, y, true); -- Check for coastal land is enabled.
					iGlobalFertilityOfLands = iGlobalFertilityOfLands + plotFertility;
					--
					if TestMembership(land_area_IDs, iArea) == false then -- This plot is the first detected in its AreaID.
						iNumLandAreas = iNumLandAreas + 1;
						table.insert(land_area_IDs, iArea);
						land_area_plots[iArea] = 1;
						land_area_fert[iArea] = plotFertility;
					else -- This AreaID already known.
						land_area_plots[iArea] = land_area_plots[iArea] + 1;
						land_area_fert[iArea] = land_area_fert[iArea] + plotFertility;
					end
				end
			end
		end
		
		--[[ Debug printout
		print("* * * * * * * * * *");
		for area_loop, AreaID in ipairs(land_area_IDs) do
			print("Area ID " .. AreaID .. " is land.");
		end ]]--
		print("* * * * * * * * * *");
		for AreaID, fert in pairs(land_area_fert) do
			print("Area ID " .. AreaID .. " has fertility of " .. fert);
		end
		print("* * * * * * * * * *");
		--		
		
		-- Sort areas, achieving a list of AreaIDs with best areas first.
		--
		-- Fertility data in land_area_fert is stored with areaID index keys.
		-- Need to generate a version of this table with indices of 1 to n, where n is number of land areas.
		local interim_table = {};
		for loop_index, data_entry in pairs(land_area_fert) do
			table.insert(interim_table, data_entry);
		end
		
		--[[for AreaID, fert in ipairs(interim_table) do
			print("Interim Table ID " .. AreaID .. " has fertility of " .. fert);
		end
		print("* * * * * * * * * *"); ]]--
		
		-- Sort the fertility values stored in the interim table. Sort order in Lua is lowest to highest.
		table.sort(interim_table);

		for AreaID, fert in ipairs(interim_table) do
			print("Interim Table ID " .. AreaID .. " has fertility of " .. fert);
		end
		print("* * * * * * * * * *");

		-- If less players than landmasses, we will ignore the extra landmasses.
		local iNumRelevantLandAreas = math.min(iNumLandAreas, self.iNumCivs);
		-- Now re-match the AreaID numbers with their corresponding fertility values
		-- by comparing the original fertility table with the sorted interim table.
		-- During this comparison, best_areas will be constructed from sorted AreaIDs, richest stored first.
		local best_areas = {};
		-- Currently, the best yields are at the end of the interim table. We need to step backward from there.
		local end_of_interim_table = table.maxn(interim_table);
		-- We may not need all entries in the table. Process only iNumRelevantLandAreas worth of table entries.
		local fertility_value_list = {};
		local fertility_value_tie = false;
		for tableConstructionLoop = end_of_interim_table, (end_of_interim_table - iNumRelevantLandAreas + 1), -1 do
			if TestMembership(fertility_value_list, interim_table[tableConstructionLoop]) == true then
				fertility_value_tie = true;
				print("*** WARNING: Fertility Value Tie exists! ***");
			else
				table.insert(fertility_value_list, interim_table[tableConstructionLoop]);
			end
		end

		if fertility_value_tie == false then -- No ties, so no need of special handling for ties.
			for areaTestLoop = end_of_interim_table, (end_of_interim_table - iNumRelevantLandAreas + 1), -1 do
				for loop_index, AreaID in ipairs(land_area_IDs) do
					if interim_table[areaTestLoop] == land_area_fert[land_area_IDs[loop_index]] then
						table.insert(best_areas, AreaID);
						break
					end
				end
			end
		else -- Ties exist! Special handling required to protect against a shortfall in the number of defined regions.
			local iNumUniqueFertValues = table.maxn(fertility_value_list);
			for fertLoop = 1, iNumUniqueFertValues do
				for AreaID, fert in pairs(land_area_fert) do
					if fert == fertility_value_list[fertLoop] then
						-- Add ties only if there is room!
						local best_areas_length = table.maxn(best_areas);
						if best_areas_length < iNumRelevantLandAreas then
							table.insert(best_areas, AreaID);
						else
							break
						end
					end
				end
			end
		end
				
		-- Debug printout
		print("-"); print("--- Continental Division, Initial Readout ---"); print("-");
		print("- Global Fertility:", iGlobalFertilityOfLands);
		print("- Total Land Plots:", iNumLandPlots);
		print("- Total Areas:", iNumLandAreas);
		print("- Relevant Areas:", iNumRelevantLandAreas); print("-");
		--

		-- Debug printout
		print("* * * * * * * * * *");
		for area_loop, AreaID in ipairs(best_areas) do
			print("Area ID " .. AreaID .. " has fertility of " .. land_area_fert[AreaID]);
		end
		print("* * * * * * * * * *");
		--

		-- Assign continents to receive start plots. Record number of civs assigned to each landmass.
		local inhabitedAreaIDs = {};
		local numberOfCivsPerArea = table.fill(0, iNumRelevantLandAreas); -- Indexed in synch with best_areas. Use same index to match values from each table.
		for civToAssign = 1, self.iNumCivs do
			local bestRemainingArea;
			local bestRemainingFertility = 0;
			local bestAreaTableIndex;
			-- Loop through areas, find the one with the best remaining fertility (civs added 
			-- to a landmass reduces its fertility rating for subsequent civs).
			--
			print("- - Searching landmasses in order to place Civ #", civToAssign); print("-");
			for area_loop, AreaID in ipairs(best_areas) do
				local thisLandmassCurrentFertility = land_area_fert[AreaID] / (1 + numberOfCivsPerArea[area_loop]);
				if thisLandmassCurrentFertility > bestRemainingFertility then
					bestRemainingArea = AreaID;
					bestRemainingFertility = thisLandmassCurrentFertility;
					bestAreaTableIndex = area_loop;
					--
					print("- Found new candidate landmass with Area ID#:", bestRemainingArea, " with fertility of ", bestRemainingFertility);
				end
			end
			-- Record results for this pass. (A landmass has been assigned to receive one more start point than it previously had).
			numberOfCivsPerArea[bestAreaTableIndex] = numberOfCivsPerArea[bestAreaTableIndex] + 1;
			if TestMembership(inhabitedAreaIDs, bestRemainingArea) == false then
				table.insert(inhabitedAreaIDs, bestRemainingArea);
			end
			print("Civ #", civToAssign, "has been assigned to Area#", bestRemainingArea); print("-");
		end
		print("-"); print("--- End of Initial Readout ---"); print("-");
		
		print("*** Number of Civs per Landmass - Table Readout ***");
		PrintContentsOfTable(numberOfCivsPerArea)
		print("--- End of Civs per Landmass readout ***"); print("-"); print("-");
				
		-- Loop through the list of inhabited landmasses, dividing each landmass in to regions.
		-- Note that it is OK to divide a continent with one civ on it: this will assign the whole
		-- of the landmass to a single region, and is the easiest method of recording such a region.
		local iNumInhabitedLandmasses = table.maxn(inhabitedAreaIDs);
		for loop, currentLandmassID in ipairs(inhabitedAreaIDs) do
			-- Obtain the boundaries of and data for this landmass.
			local landmass_data = ObtainLandmassBoundaries(currentLandmassID);
			local iWestX = landmass_data[1];
			local iSouthY = landmass_data[2];
			local iEastX = landmass_data[3];
			local iNorthY = landmass_data[4];
			local iWidth = landmass_data[5];
			local iHeight = landmass_data[6];
			local wrapsX = landmass_data[7];
			local wrapsY = landmass_data[8];
			-- Obtain "Start Placement Fertility" of the current landmass. (Necessary to do this
			-- again because the fert_table can't be built prior to finding boundaries, and we had
			-- to ID the proper landmasses via fertility to be able to figure out their boundaries.
			local fert_table, fertCount, plotCount = self:MeasureStartPlacementFertilityOfLandmass(currentLandmassID, 
		  	                                         iWestX, iEastX, iSouthY, iNorthY, wrapsX, wrapsY);
			-- Assemble the rectangle data for this landmass.
			local rect_table = {iWestX, iSouthY, iWidth, iHeight, currentLandmassID, fertCount, plotCount};
			-- Divide this landmass in to number of regions equal to civs assigned here.
			iNumCivsOnThisLandmass = numberOfCivsPerArea[loop];
			if iNumCivsOnThisLandmass > 0 and iNumCivsOnThisLandmass <= 22 then -- valid number of civs.
			
				-- Debug printout for regional division inputs.
				print("-"); print("- Region #: ", loop);
				print("- Civs on this landmass: ", iNumCivsOnThisLandmass);
				print("- Area ID#: ", currentLandmassID);
				print("- Fertility: ", fertCount);
				print("- Plot Count: ", plotCount); print("-");
				--
			
				self:DivideIntoRegions(iNumCivsOnThisLandmass, fert_table, rect_table)
			else
				print("Invalid number of civs assigned to a landmass: ", iNumCivsOnThisLandmass);
			end
		end
		--
		-- The regions have been defined.
	end
	
	-- Entry point for easier overrides.
	self:CustomOverride()
	
	-- Printout is for debugging only. Deactivate otherwise.
	local tempRegionData = self.regionData;
	for i, data in ipairs(tempRegionData) do
		print("-");
		print("Data for Start Region #", i);
		print("WestX:  ", data[1]);
		print("SouthY: ", data[2]);
		print("Width:  ", data[3]);
		print("Height: ", data[4]);
		print("AreaID: ", data[5]);
		print("Fertility:", data[6]);
		print("Plots:  ", data[7]);
		print("Fert/Plot:", data[8]);
		print("-");
	end
	--
end
------------------------------------------------------------------------------
function AssignStartingPlots:GetWorldLuxuryTargetNumbers()
	-- This data was separated out to allow easy replacement in map scripts.
	--
	-- The first number is the target for total luxuries in the world, NOT
	-- counting the one-per-civ "second type" added at start locations.
	--
	-- The second number affects minimum number of random luxuries placed.
	-- I say "affects" because it is only one part of the formula.
	local res = Map.GetCustomOption(5);
	local worldsizes = {};
	if res == 1 then -- Sparse
		worldsizes = {
			[GameInfo.Worlds.WORLDSIZE_DUEL.ID] = {14, 3},
			[GameInfo.Worlds.WORLDSIZE_TINY.ID] = {24, 4},
			[GameInfo.Worlds.WORLDSIZE_SMALL.ID] = {36, 4},
			[GameInfo.Worlds.WORLDSIZE_STANDARD.ID] = {48, 5},
			[GameInfo.Worlds.WORLDSIZE_LARGE.ID] = {60, 5},
			[GameInfo.Worlds.WORLDSIZE_HUGE.ID] = {76, 6}
		}
	elseif res == 3 then -- Abundant
		worldsizes = {
			[GameInfo.Worlds.WORLDSIZE_DUEL.ID] = {24, 3},
			[GameInfo.Worlds.WORLDSIZE_TINY.ID] = {40, 4},
			[GameInfo.Worlds.WORLDSIZE_SMALL.ID] = {60, 4},
			[GameInfo.Worlds.WORLDSIZE_STANDARD.ID] = {80, 5},
			[GameInfo.Worlds.WORLDSIZE_LARGE.ID] = {100, 5},
			[GameInfo.Worlds.WORLDSIZE_HUGE.ID] = {128, 6}
		}
	else -- Standard
		worldsizes = {
			[GameInfo.Worlds.WORLDSIZE_DUEL.ID] = {18, 3},
			[GameInfo.Worlds.WORLDSIZE_TINY.ID] = {30, 4},
			[GameInfo.Worlds.WORLDSIZE_SMALL.ID] = {45, 4},
			[GameInfo.Worlds.WORLDSIZE_STANDARD.ID] = {60, 5},
			[GameInfo.Worlds.WORLDSIZE_LARGE.ID] = {75, 5},
			[GameInfo.Worlds.WORLDSIZE_HUGE.ID] = {95, 6}
		}
	end
	local world_size_data = worldsizes[Map.GetWorldSize()];
	return world_size_data
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceLuxuries()
	-- This function is dependent upon AssignLuxuryRoles() and PlaceCityStates() having been executed first.
	local iW, iH = Map.GetGridSize();
	local res = Map.GetCustomOption(5);
	-- Place Luxuries at civ start locations.
	for loop, reg_data in ipairs(self.regions_sorted_by_type) do
		local region_number = reg_data[1];
		local this_region_luxury = reg_data[2];
		local x = self.startingPlots[region_number][1];
		local y = self.startingPlots[region_number][2];
		print("-"); print("Attempting to place Luxury#", this_region_luxury, "at start plot", x, y, "in Region#", region_number);
		-- Determine number to place at the start location
		local iNumToPlace = 1;
		if res == 4 then -- Legendary Start
			iNumToPlace = 2;
		end
		if self.regionData[region_number][8] < 2.5 then -- Low fertility per region rectangle plot, add a lux.
			--print("-"); print("Region#", region_number, "has low rectangle fertility, giving it an extra Luxury at start plot.");
			iNumToPlace = iNumToPlace + 1;
			self.luxury_low_fert_compensation[this_region_luxury] = self.luxury_low_fert_compensation[this_region_luxury] + 1;
			self.region_low_fert_compensation[region_number] = self.region_low_fert_compensation[region_number] + 1;
		end
		if self.regionData[region_number][6] / self.regionTerrainCounts[region_number][2] < 4 then -- Low fertility per land plot.
			--print("-"); print("Region#", region_number, "has low per-plot fertility, giving it an extra Luxury at start plot.");
			iNumToPlace = iNumToPlace + 1;
			self.luxury_low_fert_compensation[this_region_luxury] = self.luxury_low_fert_compensation[this_region_luxury] + 1;
			self.region_low_fert_compensation[region_number] = self.region_low_fert_compensation[region_number] + 1;
		end
		-- Obtain plot lists appropriate to this luxury type.
		local primary, secondary, tertiary, quaternary, luxury_plot_lists, shuf_list;
		primary, secondary, tertiary, quaternary = self:GetIndicesForLuxuryType(this_region_luxury);
		luxury_plot_lists = self:GenerateLuxuryPlotListsAtCitySite(x, y, 2, false)

		-- First pass, checking only first two rings with a 50% ratio.
		shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[primary])
		local iNumLeftToPlace = self:PlaceSpecificNumberOfResources(this_region_luxury, 1, iNumToPlace, 0.5, -1, 0, 0, shuf_list);
		if iNumLeftToPlace > 0 and secondary > 0 then
			shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[secondary])
			iNumLeftToPlace = self:PlaceSpecificNumberOfResources(this_region_luxury, 1, iNumLeftToPlace, 0.5, -1, 0, 0, shuf_list);
		end
		if iNumLeftToPlace > 0 and tertiary > 0 then
			shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[tertiary])
			iNumLeftToPlace = self:PlaceSpecificNumberOfResources(this_region_luxury, 1, iNumLeftToPlace, 0.5, -1, 0, 0, shuf_list);
		end
		if iNumLeftToPlace > 0 and quaternary > 0 then
			shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[quaternary])
			iNumLeftToPlace = self:PlaceSpecificNumberOfResources(this_region_luxury, 1, iNumLeftToPlace, 0.5, -1, 0, 0, shuf_list);
		end

		if iNumLeftToPlace > 0 then
			-- Second pass, checking three rings with a 100% ratio.
			luxury_plot_lists = self:GenerateLuxuryPlotListsAtCitySite(x, y, 3, false)
			shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[primary])
			iNumLeftToPlace = self:PlaceSpecificNumberOfResources(this_region_luxury, 1, iNumLeftToPlace, 1, -1, 0, 0, shuf_list);
			if iNumLeftToPlace > 0 and secondary > 0 then
				shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[secondary])
				iNumLeftToPlace = self:PlaceSpecificNumberOfResources(this_region_luxury, 1, iNumLeftToPlace, 1, -1, 0, 0, shuf_list);
			end
			if iNumLeftToPlace > 0 and tertiary > 0 then
				shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[tertiary])
				iNumLeftToPlace = self:PlaceSpecificNumberOfResources(this_region_luxury, 1, iNumLeftToPlace, 1, -1, 0, 0, shuf_list);
			end
			if iNumLeftToPlace > 0 and quaternary > 0 then
				shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[quaternary])
				iNumLeftToPlace = self:PlaceSpecificNumberOfResources(this_region_luxury, 1, iNumLeftToPlace, 1, -1, 0, 0, shuf_list);
			end
		end

		if iNumLeftToPlace > 0 then
			-- If we haven't been able to place all of this lux type at the start, it CAN be placed
			-- in the region somewhere. Subtract remainder from this region's compensation, so that the
			-- regional process, later, will attempt to place this remainder somewhere in the region.
			self.luxury_low_fert_compensation[this_region_luxury] = self.luxury_low_fert_compensation[this_region_luxury] - iNumLeftToPlace;
			self.region_low_fert_compensation[region_number] = self.region_low_fert_compensation[region_number] - iNumLeftToPlace;
		end
		if iNumLeftToPlace > 0 and self.iNumTypesRandom > 0 then
			-- We'll attempt to place one source of a Luxury type assigned to random distribution.
			local randoms_to_place = 1;
			for loop, random_res in ipairs(self.resourceIDs_assigned_to_random) do
		 		primary, secondary, tertiary, quaternary = self:GetIndicesForLuxuryType(random_res);
		 		if randoms_to_place > 0 then
					shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[primary])
					randoms_to_place = self:PlaceSpecificNumberOfResources(random_res, 1, 1, 1, -1, 0, 0, shuf_list);
				end
				if randoms_to_place > 0 and secondary > 0 then
					shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[secondary])
					randoms_to_place = self:PlaceSpecificNumberOfResources(random_res, 1, 1, 1, -1, 0, 0, shuf_list);
				end
				if randoms_to_place > 0 and tertiary > 0 then
					shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[tertiary])
					randoms_to_place = self:PlaceSpecificNumberOfResources(random_res, 1, 1, 1, -1, 0, 0, shuf_list);
				end
				if randoms_to_place > 0 and quaternary > 0 then
					shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[quaternary])
					randoms_to_place = self:PlaceSpecificNumberOfResources(random_res, 1, 1, 1, -1, 0, 0, shuf_list);
				end
			end
		end
	end
	
	-- Place Luxuries at City States.
	-- Candidates include luxuries exclusive to CS, the lux assigned to this CS's region (if in a region), and the randoms.
	for city_state = 1, self.iNumCityStates do
		-- First check to see if this city state number received a valid start plot.
		if self.city_state_validity_table[city_state] == false then
			-- This one did not! It does not exist on the map nor have valid data, so we will ignore it.
		else
			-- OK, it's a valid city state. Process it.
			local region_number = self.city_state_region_assignments[city_state];
			local x = self.cityStatePlots[city_state][1];
			local y = self.cityStatePlots[city_state][2];
			local allowed_luxuries = self:GetListOfAllowableLuxuriesAtCitySite(x, y, 2)
			local lux_possible_for_cs = {}; -- Recorded with ID as key, weighting as data entry
			-- Identify Allowable Luxuries assigned to City States.
			-- If any CS-Only types are eligible, then all combined will have a weighting of 75%
			local cs_only_types = {};
			for loop, res_ID in ipairs(self.resourceIDs_assigned_to_cs) do
				if allowed_luxuries[res_ID] == true then
					table.insert(cs_only_types, res_ID);
				end
			end
			local iNumCSAllowed = table.maxn(cs_only_types);
			if iNumCSAllowed > 0 then
				for loop, res_ID in ipairs(cs_only_types) do
					lux_possible_for_cs[res_ID] = 75 / iNumCSAllowed;
				end
			end
			-- Identify Allowable Random Luxuries and the Regional Luxury if any.
			-- If any random types are eligible (plus the regional type if in a region) these combined carry a 25% weighting.
			if self.iNumTypesRandom > 0 or region_number > 0 then
				local random_types_allowed = {};
				for loop, res_ID in ipairs(self.resourceIDs_assigned_to_random) do
					if allowed_luxuries[res_ID] == true then
						table.insert(random_types_allowed, res_ID);
					end
				end
				local iNumRandAllowed = table.maxn(random_types_allowed);
				local iNumAllowed = iNumRandAllowed;
				if region_number > 0 then
					iNumAllowed = iNumAllowed + 1; -- Adding the region type in to the mix with the random types.
					local res_ID = self.region_luxury_assignment[region_number];
					if allowed_luxuries[res_ID] == true then
						lux_possible_for_cs[res_ID] = 25 / iNumAllowed;
					end
				end
				if iNumRandAllowed > 0 then
					for loop, res_ID in ipairs(random_types_allowed) do
						lux_possible_for_cs[res_ID] = 25 / iNumAllowed;
					end
				end
			end

			-- If there are no allowable luxury types at this city site, then this city state gets none.
			local iNumAvailableTypes = table.maxn(lux_possible_for_cs);
			if iNumAvailableTypes == 0 then
				--print("City State #", city_state, "has poor land, ineligible to receive a Luxury resource.");
			else
				-- Calculate probability thresholds for each allowable luxury type.
				local res_threshold = {};
				local totalWeight, accumulatedWeight = 0, 0;
				for res_ID, this_weight in pairs(lux_possible_for_cs) do
					totalWeight = totalWeight + this_weight;
				end
				for res_ID, this_weight in pairs(lux_possible_for_cs) do
					local threshold = (this_weight + accumulatedWeight) * 10000 / totalWeight;
					res_threshold[res_ID] = threshold;
					accumulatedWeight = accumulatedWeight + this_weight;
				end
				-- Choose luxury type.
				local use_this_ID;
				local diceroll = Map.Rand(10000, "Choose resource type - Assign Luxury To City State - Lua");
				for res_ID, threshold in pairs(res_threshold) do
					if diceroll < threshold then -- Choose this resource type.
						use_this_ID = res_ID;
						break
					end
				end
				print("-"); print("-"); print("-Assigned Luxury Type", use_this_ID, "to City State#", city_state);
				-- Place luxury.
				local primary, secondary, tertiary, quaternary, luxury_plot_lists, shuf_list;
				primary, secondary, tertiary, quaternary = self:GetIndicesForLuxuryType(use_this_ID);
				luxury_plot_lists = self:GenerateLuxuryPlotListsAtCitySite(x, y, 2, false)
				shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[primary])
				local iNumLeftToPlace = self:PlaceSpecificNumberOfResources(use_this_ID, 1, 1, 1, -1, 0, 0, shuf_list);
				if iNumLeftToPlace > 0 and secondary > 0 then
					shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[secondary])
					iNumLeftToPlace = self:PlaceSpecificNumberOfResources(use_this_ID, 1, 1, 1, -1, 0, 0, shuf_list);
				end
				if iNumLeftToPlace > 0 and tertiary > 0 then
					shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[tertiary])
					iNumLeftToPlace = self:PlaceSpecificNumberOfResources(use_this_ID, 1, 1, 1, -1, 0, 0, shuf_list);
				end
				if iNumLeftToPlace > 0 and quaternary > 0 then
					shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[quaternary])
					iNumLeftToPlace = self:PlaceSpecificNumberOfResources(use_this_ID, 1, 1, 1, -1, 0, 0, shuf_list);
				end
				--if iNumLeftToPlace == 0 then
					--print("-"); print("Placed Luxury ID#", use_this_ID, "at City State#", city_state, "in Region#", region_number, "located at Plot", x, y);
				--end
			end
		end
	end
		
	-- Place Regional Luxuries
	for region_number, res_ID in ipairs(self.region_luxury_assignment) do
		print("-"); print("- - -"); print("Attempting to place regional luxury #", res_ID, "in Region#", region_number);
		local iNumAlreadyPlaced = self.amounts_of_resources_placed[res_ID + 1];
		local assignment_split = self.luxury_assignment_count[res_ID];
		local primary, secondary, tertiary, quaternary, luxury_plot_lists, shuf_list, iNumLeftToPlace;
		primary, secondary, tertiary, quaternary = self:GetIndicesForLuxuryType(res_ID);
		luxury_plot_lists = self:GenerateLuxuryPlotListsInRegion(region_number)

		-- Calibrate number of luxuries per region to world size and number of civs
		-- present. The amount of lux per region should be at its highest when the 
		-- number of civs in the game is closest to "default" for that map size.
		local target_list = self:GetRegionLuxuryTargetNumbers()
		local targetNum = target_list[self.iNumCivs]
		-- local targetNum = math.floor((target_list[self.iNumCivs] + (0.5 * self.luxury_low_fert_compensation[res_ID])) / assignment_split);
		targetNum = targetNum - self.region_low_fert_compensation[region_number];
		-- Adjust target number according to Resource Setting.
		if res == 1 then
			targetNum = targetNum - 1;
		elseif res == 3 or res == 6 then
			targetNum = targetNum + 1
		end
		local iNumThisLuxToPlace = math.max(1, targetNum); -- Always place at least one.

		--print("-"); print("Target number for Luxury#", res_ID, "with assignment split of", assignment_split, "is", targetNum);
		
		-- Place luxuries.
		shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[primary])
		iNumLeftToPlace = self:PlaceSpecificNumberOfResources(res_ID, 1, iNumThisLuxToPlace, 0.3, 2, 0, 3, shuf_list);
		if iNumLeftToPlace > 0 and secondary > 0 then
			shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[secondary])
			iNumLeftToPlace = self:PlaceSpecificNumberOfResources(res_ID, 1, iNumLeftToPlace, 0.3, 2, 0, 3, shuf_list);
		end
		if iNumLeftToPlace > 0 and tertiary > 0 then
			shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[tertiary])
			iNumLeftToPlace = self:PlaceSpecificNumberOfResources(res_ID, 1, iNumLeftToPlace, 0.4, 2, 0, 2, shuf_list);
		end
		if iNumLeftToPlace > 0 and quaternary > 0 then
			shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[quaternary])
			iNumLeftToPlace = self:PlaceSpecificNumberOfResources(res_ID, 1, iNumLeftToPlace, 0.5, 2, 0, 2, shuf_list);
		end
		--print("-"); print("-"); print("Number of LuxuryID", res_ID, "left to place in Region#", region_number, "is", iNumLeftToPlace);
	end

	-- Place Random Luxuries
	if self.iNumTypesRandom > 0 then
		print("* *"); print("* iNumTypesRandom = ", self.iNumTypesRandom); print("* *");
		-- This table governs targets for total number of luxuries placed in the world, not
		-- including the "extra types" of Luxuries placed at start locations. These targets
		-- are approximate. An additional random factor is added in based on number of civs.
		-- Any difference between regional and city state luxuries placed, and the target, is
		-- made up for with the number of randomly placed luxuries that get distributed.
		local world_size_data = self:GetWorldLuxuryTargetNumbers()
		local targetLuxForThisWorldSize = world_size_data[1];
		local loopTarget = world_size_data[2];
		local extraLux = Map.Rand(self.iNumCivs, "Luxury Resource Variance - Place Resources LUA");
		local iNumRandomLuxTarget = targetLuxForThisWorldSize + extraLux - self.totalLuxPlacedSoFar;
		
		if self.iNumTypesRandom * 3 > iNumRandomLuxTarget then
			print ("iNumRandomLuxTarget = " .. tostring(iNumRandomLuxTarget) .. ". Just putting in 3 of each random.");
		end
		
		local iNumRandomLuxPlaced, iNumThisLuxToPlace = 0, 0;
		-- This table weights the amount of random luxuries to place, with first-selected getting heavier weighting.
		local random_lux_ratios_table = {
		{1},
		{0.55, 0.45},
		{0.40, 0.33, 0.27},
		{0.35, 0.25, 0.25, 0.15},
		{0.25, 0.25, 0.20, 0.15, 0.15},
		{0.20, 0.20, 0.20, 0.15, 0.15, 0.10},
		{0.20, 0.20, 0.15, 0.15, 0.10, 0.10, 0.10},
		{0.20, 0.15, 0.15, 0.10, 0.10, 0.10, 0.10, 0.10} };

		for loop, res_ID in ipairs(self.resourceIDs_assigned_to_random) do
			local primary, secondary, tertiary, quaternary, luxury_plot_lists, current_list, iNumLeftToPlace;
			primary, secondary, tertiary, quaternary = self:GetIndicesForLuxuryType(res_ID);
			
			-- If calculated number of randoms is low, just place 3 of each
			if self.iNumTypesRandom * 3 > iNumRandomLuxTarget then
				iNumThisLuxToPlace = 3;
				
			elseif self.iNumTypesRandom > 8 then
				iNumThisLuxToPlace = math.max(3, math.ceil(iNumRandomLuxTarget / 10));
				
			else
				local lux_minimum = math.max(3, loopTarget - loop);
				local lux_share_of_remaining = math.ceil(iNumRandomLuxTarget * random_lux_ratios_table[self.iNumTypesRandom][loop]);
				iNumThisLuxToPlace = math.max(lux_minimum, lux_share_of_remaining);
			end
			-- Place this luxury type.
			current_list = self.global_luxury_plot_lists[primary];
			iNumLeftToPlace = self:PlaceSpecificNumberOfResources(res_ID, 1, iNumThisLuxToPlace, 0.25, 2, 4, 6, current_list);
			if iNumLeftToPlace > 0 and secondary > 0 then
				current_list = self.global_luxury_plot_lists[secondary];
				iNumLeftToPlace = self:PlaceSpecificNumberOfResources(res_ID, 1, iNumLeftToPlace, 0.25, 2, 4, 6, current_list);
			end
			if iNumLeftToPlace > 0 and tertiary > 0 then
				current_list = self.global_luxury_plot_lists[tertiary];
				iNumLeftToPlace = self:PlaceSpecificNumberOfResources(res_ID, 1, iNumLeftToPlace, 0.25, 2, 4, 6, current_list);
			end
			if iNumLeftToPlace > 0 and quaternary > 0 then
				current_list = self.global_luxury_plot_lists[quaternary];
				iNumLeftToPlace = self:PlaceSpecificNumberOfResources(res_ID, 1, iNumLeftToPlace, 0.3, 2, 4, 6, current_list);
			end
			iNumRandomLuxPlaced = iNumRandomLuxPlaced + iNumThisLuxToPlace - iNumLeftToPlace;
			print("-"); print("Random Luxury Target Number:", iNumThisLuxToPlace);
			print("Random Luxury Target Placed:", iNumThisLuxToPlace - iNumLeftToPlace); print("-");
		end

		--[[
		print("-"); print("+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+");
		print("+ Random Luxuries Target Number:", iNumRandomLuxTarget);
		print("+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+");
		print("+ Random Luxuries Number Placed:", iNumRandomLuxPlaced);
		print("+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+"); print("-");
		]]--

	end

	-- For Resource settings other than Sparse, add a second luxury type at start locations.
	-- This second type will be selected from Random types if possible, CS types if necessary, and other regions' types as a final fallback.
	-- Marble is included in the types possible to be placed.
	if res ~= 1 then
		local diceroll = 1
		local old__diceroll
		local region_number = 1
		for region_number = 1, self.iNumCivs do
			local x = self.startingPlots[region_number][1];
			local y = self.startingPlots[region_number][2];
			local use_this_ID;
			local candidate_types, iNumTypesAllowed = {}, 0;
			local allowed_luxuries = self:GetListOfAllowableLuxuriesAtCitySite(x, y, 2)
			print("-"); print("--- Eligible Types List for Second Luxury in Region#", region_number, "---");
			-- See if any Random types are eligible.
			for loop, res_ID in ipairs(self.resourceIDs_assigned_to_random) do
				if allowed_luxuries[res_ID] == true then
					--print("- Found eligible luxury type:", res_ID);
					iNumTypesAllowed = iNumTypesAllowed + 1;
					table.insert(candidate_types, res_ID);
				end
			end
			-- Check to see if any Special Case luxuries are eligible. Disallow if Strategic Balance resource setting.
			if res ~= 5 and res ~= 6 then
				for loop, res_ID in ipairs(self.resourceIDs_assigned_to_special_case) do
					if allowed_luxuries[res_ID] == true then
						print("- Found eligible luxury type:", res_ID);
						iNumTypesAllowed = iNumTypesAllowed + 1;
						table.insert(candidate_types, res_ID);
					end
				end
			end
		
			if iNumTypesAllowed > 0 then
				diceroll = 1 + Map.Rand(iNumTypesAllowed, "Choosing second luxury type at a start location - LUA");
				use_this_ID = candidate_types[diceroll];
			else
				-- See if any City State types are eligible.
				for loop, res_ID in ipairs(self.resourceIDs_assigned_to_cs) do
					if allowed_luxuries[res_ID] == true then
						print("- Found eligible luxury type:", res_ID);
						iNumTypesAllowed = iNumTypesAllowed + 1;
						table.insert(candidate_types, res_ID);
					end
				end
				if iNumTypesAllowed > 0 then
					local diceroll = 1 + Map.Rand(iNumTypesAllowed, "Choosing second luxury type at a start location - LUA");
					use_this_ID = candidate_types[diceroll];
				else
					-- See if anybody else's regional type is eligible.
					local region_lux_ID = self.region_luxury_assignment[region_number];
					for loop, res_ID in ipairs(self.resourceIDs_assigned_to_regions) do
						if res_ID ~= region_lux_ID then
							if allowed_luxuries[res_ID] == true then
								print("- Found eligible luxury type:", res_ID);
								iNumTypesAllowed = iNumTypesAllowed + 1;
								table.insert(candidate_types, res_ID);
							end
						end
					end
					if iNumTypesAllowed > 0 then
						local diceroll = 1 + Map.Rand(iNumTypesAllowed, "Choosing second luxury type at a start location - LUA");
						use_this_ID = candidate_types[diceroll];
					else
						print("-"); print("Failed to place second Luxury type at start in Region#", region_number, "-- no eligible types!"); print("-");
					end
				end
			end
			print("--- End of Eligible Types list for Second Luxury in Region#", region_number, "---");
			for attempt = 1, iNumTypesAllowed do
				if use_this_ID ~= nil then -- Place this luxury type at this start.
					local primary, secondary, tertiary, quaternary, luxury_plot_lists, shuf_list;
					primary, secondary, tertiary, quaternary = self:GetIndicesForLuxuryType(use_this_ID);
					luxury_plot_lists = self:GenerateLuxuryPlotListsAtCitySite(x, y, 2, false)
					shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[primary])
					local iNumLeftToPlace = self:PlaceSpecificNumberOfResources(use_this_ID, 1, 1, 1, -1, 0, 0, shuf_list);
					if iNumLeftToPlace > 0 and secondary > 0 then
						shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[secondary])
						iNumLeftToPlace = self:PlaceSpecificNumberOfResources(use_this_ID, 1, 1, 1, -1, 0, 0, shuf_list);
					end
					if iNumLeftToPlace > 0 and tertiary > 0 then
						shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[tertiary])
						iNumLeftToPlace = self:PlaceSpecificNumberOfResources(use_this_ID, 1, 1, 1, -1, 0, 0, shuf_list);
					end
					if iNumLeftToPlace > 0 and quaternary > 0 then
						shuf_list = GetShuffledCopyOfTable(luxury_plot_lists[quaternary])
						iNumLeftToPlace = self:PlaceSpecificNumberOfResources(use_this_ID, 1, 1, 1, -1, 0, 0, shuf_list);
					end
					if iNumLeftToPlace == 0 then
						print("-"); print("Placed Second Luxury type of ID#", use_this_ID, "for start located at Plot", x, y, " in Region#", region_number);
						-- region_number = region_number + 1;
						break
					else
						if diceroll == iNumTypesAllowed then
							diceroll = 0;
						end
						diceroll = diceroll + 1;
						use_this_ID = candidate_types[diceroll]
						-- print("-Failed-")
					end
				end
			end
		end
	end

	-- Handle Special Case Luxuries
	if self.iNumTypesSpecialCase > 0 then
		-- Add a special case function for each luxury to be handled as a special case.
		self:PlaceMarble()
	end

end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceMarble()
	local marble_already_placed = self.amounts_of_resources_placed[self.marble_ID + 1];
	local marble_target = math.ceil(self.iNumCivs * 0.75);
	local res = Map.GetCustomOption(5);
	if res == 1 then
		marble_target = math.ceil(self.iNumCivs * 0.5);
	elseif res == 3 then
		marble_target = math.ceil(self.iNumCivs * 0.9);
	end
	local iNumMarbleToPlace = math.max(2, marble_target - marble_already_placed);
	local iW, iH = Map.GetGridSize();
	local iNumLeftToPlace = iNumMarbleToPlace;
	local iNumPlots = table.maxn(self.marble_list);
	if iNumPlots < 1 then
		--print("No eligible plots available to place Marble!");
		return
	end
	-- Main loop
	for place_resource = 1, iNumMarbleToPlace do
		for loop, plotIndex in ipairs(self.marble_list) do
			if self.marbleData[plotIndex] == 0 and self.luxuryData[plotIndex] == 0 then
				local x = (plotIndex - 1) % iW;
				local y = (plotIndex - x - 1) / iW;
				local res_plot = Map.GetPlot(x, y)
				if res_plot:GetResourceType(-1) == -1 then -- Placing this resource in this plot.
					res_plot:SetResourceType(self.marble_ID, 1);
					self.amounts_of_resources_placed[self.marble_ID + 1] = self.amounts_of_resources_placed[self.marble_ID + 1] + 1;
					--print("-"); print("Placed Marble randomly at Plot", x, y);
					self.totalLuxPlacedSoFar = self.totalLuxPlacedSoFar + 1;
					iNumLeftToPlace = iNumLeftToPlace - 1;
					--print("Still need to place", iNumLeftToPlace, "more units of Marble.");
					self:PlaceResourceImpact(x, y, 2, 1)
					self:PlaceResourceImpact(x, y, 7, 6)
					break
				end
			end
		end
	end
	if iNumLeftToPlace > 0 then
		print("Failed to place", iNumLeftToPlace, "units of Marble.");
	end
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceOilInTheSea()
	-- Places sources of Oil in Coastal waters, equal to half what's on the 
	-- land. If the map has too little ocean, then whatever will fit.
	--
	-- WARNING: This operation will render the Strategic Resource Impact Table useless for
	-- further operations, so should always be called last, even after minor placements.
	local sea_oil_amt = 4;
	local res = Map.GetCustomOption(5);
	if res == 3 then -- Abundant Resources, increase amount.
		sea_oil_amt = 6;
	end
	local iNumLandOilUnits = self.amounts_of_resources_placed[self.oil_ID + 1];
	local iNumToPlace = math.floor((iNumLandOilUnits / 2) / sea_oil_amt);

	--print("Adding Oil resources to the Sea.");
	self:PlaceSpecificNumberOfResources(self.oil_ID, sea_oil_amt, iNumToPlace, 0.2, 1, 4, 7, self.coast_list)
end
------------------------------------------------------------------------------
function AssignStartingPlots:GetMajorStrategicResourceQuantityValues()
	-- This function determines quantity per tile for each strategic resource's major deposit size.
	-- Note: scripts that cannot place Oil in the sea need to increase amounts on land to compensate.
	local uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 4, 4, 7, 6, 7, 8;
	local res = Map.GetCustomOption(5);
	-- Check the resource setting.
	if res == 1 then -- Sparse
		uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 2, 4, 5, 4, 5, 5;
	elseif res == 3 then -- Abundant
		uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 4, 6, 9, 9, 10, 10;
	end
	return uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt
end
------------------------------------------------------------------------------
function AssignStartingPlots:GetSmallStrategicResourceQuantityValues()
	-- This function determines quantity per tile for each strategic resource's small deposit size.
	local uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 2, 2, 3, 2, 3, 3;
	local res = Map.GetCustomOption(5);
	-- Check the resource setting.
	if res == 1 then -- Sparse
		uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 1, 1, 2, 1, 2, 2;
	elseif res == 3 then -- Abundant
		uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 3, 3, 3, 3, 3, 3;
	end
	return uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt
end
------------------------------------------------------------------------------
function StartPlotSystem()
	-- Get Resources setting input by user.
	local res = Map.GetCustomOption(5)
	if res == 7 then
		res = 1 + Map.Rand(3, "Random Resources Option - Lua");
	end

	print("Creating start plot database.");
	local start_plot_database = AssignStartingPlots.Create()
	
	print("Dividing the map in to Regions.");
	-- Regional Division Method 1: Biggest Landmass
	local args = {
		method = 1,
		resources = res,
		};
	start_plot_database:GenerateRegions(args)

	print("Choosing start locations for civilizations.");
	start_plot_database:ChooseLocations()
	
	print("Normalizing start locations and assigning them to Players.");
	start_plot_database:BalanceAndAssign()

	print("Placing Natural Wonders.");
	start_plot_database:PlaceNaturalWonders()

	print("Placing Resources and City States.");
	start_plot_database:PlaceResourcesAndCityStates()
end
------------------------------------------------------------------------------