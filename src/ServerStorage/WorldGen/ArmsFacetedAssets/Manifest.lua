-- generated from art/manifests/ArmsFaceted.manifest.json (wave2/hands/tools/gen_lua_manifest.py)
return {
	SOURCE = { name = "LS_ArmsFaceted_v1", assetId = 78153646757113 },
	IMAGES = {
		ArmsFaceted_Skin_Color = 125941381612580,
		ArmsFaceted_Skin_Normal = 131554387088209,
		ArmsFaceted_Skin_Rough = 84042274742334,
		ArmsFaceted_Sleeve_Color = 85613396924504,
		ArmsFaceted_Sleeve_Normal = 76773041012836,
		ArmsFaceted_Sleeve_Rough = 105858932067299,
	},
	SLEEVE_TINT = {96, 88, 80},
	SKIN_TINT = {234, 184, 146},
	ASSETS = {
		{
			name = "R_UpperArm", origin = {0.1557, 0, 0}, bmin = {-0.1557, -0.05, -0.148}, bmax = {0.1617, 1.0683, 0.153},
			parts = {
				{ name = "R_UpperArm_Sleeve", role = "Sleeve", mat = "Fabric", rgb = {82, 75, 68}, set = "ArmsFaceted_Sleeve", tint = {96, 88, 80} },
			},
			att = {
				Shoulder = { pos = {0, 0, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
				Elbow = { pos = {0, 0.95, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
			},
		},
		{
			name = "R_Forearm", origin = {0.9567, 0, 0}, bmin = {-0.1392, -0.04, -0.121}, bmax = {0.14, 0.902, 0.1253},
			parts = {
				{ name = "R_Forearm_Skin", role = "Skin", mat = "SmoothPlastic", rgb = {217, 164, 124}, set = "ArmsFaceted_Skin", tint = {234, 184, 146} },
				{ name = "R_Forearm_Sleeve", role = "Sleeve", mat = "Fabric", rgb = {82, 75, 68}, set = "ArmsFaceted_Sleeve", tint = {96, 88, 80} },
			},
			att = {
				Elbow = { pos = {0, 0, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
				Wrist = { pos = {0, 0.85, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
			},
		},
		{
			name = "R_HandGrip", origin = {1.7405, 0, 0}, bmin = {-0.1438, -0.052, -0.061}, bmax = {0.1755, 0.3944, 0.2313},
			parts = {
				{ name = "R_HandGrip_Skin", role = "Skin", mat = "SmoothPlastic", rgb = {217, 164, 124}, set = "ArmsFaceted_Skin", tint = {234, 184, 146} },
			},
			att = {
				Wrist = { pos = {0, 0, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
				Grip = { pos = {0.0131, 0.2573, 0.1175}, look = {0.9848, 0.1736, 0}, up = {-0.1736, 0.9848, 0} },
			},
		},
		{
			name = "R_HandOpen", origin = {2.5694, 0, 0}, bmin = {-0.1534, -0.052, -0.061}, bmax = {0.2087, 0.4843, 0.2067},
			parts = {
				{ name = "R_HandOpen_Skin", role = "Skin", mat = "SmoothPlastic", rgb = {217, 164, 124}, set = "ArmsFaceted_Skin", tint = {234, 184, 146} },
			},
			att = {
				Wrist = { pos = {0, 0, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
				Palm = { pos = {0, 0.18, 0.0631}, look = {0, 0, 1}, up = {0, 1, 0} },
			},
		},
		{
			name = "R_HandFist", origin = {3.4243, 0, 0}, bmin = {-0.1462, -0.052, -0.061}, bmax = {0.157, 0.3225, 0.2344},
			parts = {
				{ name = "R_HandFist_Skin", role = "Skin", mat = "SmoothPlastic", rgb = {217, 164, 124}, set = "ArmsFaceted_Skin", tint = {234, 184, 146} },
			},
			att = {
				Wrist = { pos = {0, 0, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
				Knuckles = { pos = {0.0663, 0.3225, 0.031}, look = {0, 1, 0}, up = {0, 0, -1} },
			},
		},
		{
			name = "R_HandRelaxed", origin = {4.2336, 0, 0}, bmin = {-0.1523, -0.052, -0.061}, bmax = {0.1632, 0.5234, 0.2044},
			parts = {
				{ name = "R_HandRelaxed_Skin", role = "Skin", mat = "SmoothPlastic", rgb = {217, 164, 124}, set = "ArmsFaceted_Skin", tint = {234, 184, 146} },
			},
			att = {
				Wrist = { pos = {0, 0, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
				Palm = { pos = {0, 0.18, 0.0631}, look = {0, 0, 1}, up = {0, 1, 0} },
			},
		},
		{
			name = "L_UpperArm", origin = {5.0585, 0, 0}, bmin = {-0.1617, -0.05, -0.148}, bmax = {0.1557, 1.0683, 0.153},
			parts = {
				{ name = "L_UpperArm_Sleeve", role = "Sleeve", mat = "Fabric", rgb = {82, 75, 68}, set = "ArmsFaceted_Sleeve", tint = {96, 88, 80} },
			},
			att = {
				Shoulder = { pos = {0, 0, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
				Elbow = { pos = {0, 0.95, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
			},
		},
		{
			name = "L_Forearm", origin = {5.8542, 0, 0}, bmin = {-0.14, -0.04, -0.121}, bmax = {0.1392, 0.902, 0.1253},
			parts = {
				{ name = "L_Forearm_Skin", role = "Skin", mat = "SmoothPlastic", rgb = {217, 164, 124}, set = "ArmsFaceted_Skin", tint = {234, 184, 146} },
				{ name = "L_Forearm_Sleeve", role = "Sleeve", mat = "Fabric", rgb = {82, 75, 68}, set = "ArmsFaceted_Sleeve", tint = {96, 88, 80} },
			},
			att = {
				Elbow = { pos = {0, 0, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
				Wrist = { pos = {0, 0.85, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
			},
		},
		{
			name = "L_HandGrip", origin = {6.6689, 0, 0}, bmin = {-0.1755, -0.052, -0.061}, bmax = {0.1438, 0.3944, 0.2313},
			parts = {
				{ name = "L_HandGrip_Skin", role = "Skin", mat = "SmoothPlastic", rgb = {217, 164, 124}, set = "ArmsFaceted_Skin", tint = {234, 184, 146} },
			},
			att = {
				Wrist = { pos = {0, 0, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
				Grip = { pos = {-0.0131, 0.2573, 0.1175}, look = {-0.9848, 0.1736, 0}, up = {0.1736, 0.9848, 0} },
			},
		},
		{
			name = "L_HandOpen", origin = {7.5215, 0, 0}, bmin = {-0.2087, -0.052, -0.061}, bmax = {0.1534, 0.4843, 0.2067},
			parts = {
				{ name = "L_HandOpen_Skin", role = "Skin", mat = "SmoothPlastic", rgb = {217, 164, 124}, set = "ArmsFaceted_Skin", tint = {234, 184, 146} },
			},
			att = {
				Wrist = { pos = {0, 0, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
				Palm = { pos = {0, 0.18, 0.0631}, look = {0, 0, 1}, up = {0, 1, 0} },
			},
		},
		{
			name = "L_HandFist", origin = {8.3319, 0, 0}, bmin = {-0.157, -0.052, -0.061}, bmax = {0.1462, 0.3225, 0.2344},
			parts = {
				{ name = "L_HandFist_Skin", role = "Skin", mat = "SmoothPlastic", rgb = {217, 164, 124}, set = "ArmsFaceted_Skin", tint = {234, 184, 146} },
			},
			att = {
				Wrist = { pos = {0, 0, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
				Knuckles = { pos = {-0.0663, 0.3225, 0.031}, look = {0, 1, 0}, up = {0, 0, -1} },
			},
		},
		{
			name = "L_HandRelaxed", origin = {9.1413, 0, 0}, bmin = {-0.1632, -0.052, -0.061}, bmax = {0.1523, 0.5234, 0.2044},
			parts = {
				{ name = "L_HandRelaxed_Skin", role = "Skin", mat = "SmoothPlastic", rgb = {217, 164, 124}, set = "ArmsFaceted_Skin", tint = {234, 184, 146} },
			},
			att = {
				Wrist = { pos = {0, 0, 0}, look = {0, 1, 0}, up = {0, 0, -1} },
				Palm = { pos = {0, 0.18, 0.0631}, look = {0, 0, 1}, up = {0, 1, 0} },
			},
		},
	},
}
