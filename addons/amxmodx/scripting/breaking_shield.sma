/******************************/    HEADER    /******************************/

#include <amxmodx>
#include <fakemeta>
#include <reapi>

#define PLUGIN_NAME		"Breaking Shield"
#define PLUGIN_VERSION	"1.0.0"
#define PLUGIN_AUTHORS	"Albertio & MayroN"

/******************************/    CONSTANTS    /******************************/

#define CONFIG_FILE_PATH "addons/amxmodx/configs/breaking_shield/breaking_shield.ini"

/******************************/    GLOBAL VARIABLES    /******************************/

enum Sections {
	SECTION_NONE = -1,
	SECTION_SHIELD,
	SECTION_MODELS
};
new Sections:ParserCurSection;

enum _:ShieldDataStruct {
	Float:STRENGTH,
	Float:PISTOLS_DIVIDER,
	Float:SHOTGUNS_DIVIDER,
	Float:SMGS_DIVIDER,
	Float:RIFLES_DIVIDER,
	Float:SNIPERRIFLES_DIVIDER,
	Float:MACHINEGUNS_DIVIDER,
	Float:GRENADES_DIVIDER,
	GIBS_MODEL[MAX_RESOURCE_PATH_LENGTH],
	NULL_MODEL[MAX_RESOURCE_PATH_LENGTH],
	WORLD_MODEL[MAX_RESOURCE_PATH_LENGTH]
};
new ShieldData[ShieldDataStruct];
new ShieldModels[WeaponIdType][MAX_RESOURCE_PATH_LENGTH];
new ShieldGibsCacheId;

enum _:PlayerDataStruct {
	Float:FIRED_DAMAGE,
	Float:RECEIVED_DAMAGE,
	MODEL_ENTITY
};
new PlayerData[MAX_PLAYERS + 1][PlayerDataStruct];

new Trie:ConfigMap;

new FWD_TraceLine;
new HookChain:HC_PlayerTakeDamage;

/******************************/    CONFIGURATION    /******************************/

public plugin_precache() {
	InitConfigMap();
	ParseConfig();
	PrecacheModels();
}

public InitConfigMap() {
	ConfigMap = TrieCreate();
	
	TrieSetCell(ConfigMap, "STRENGTH", STRENGTH);

	TrieSetCell(ConfigMap, "PISTOLS_DIVIDER", PISTOLS_DIVIDER);
	TrieSetCell(ConfigMap, "SHOTGUNS_DIVIDER", SHOTGUNS_DIVIDER);
	TrieSetCell(ConfigMap, "SMGS_DIVIDER", SMGS_DIVIDER);
	TrieSetCell(ConfigMap, "RIFLES_DIVIDER", RIFLES_DIVIDER);
	TrieSetCell(ConfigMap, "SNIPERRIFLES_DIVIDER", SNIPERRIFLES_DIVIDER);
	TrieSetCell(ConfigMap, "MACHINEGUNS_DIVIDER", MACHINEGUNS_DIVIDER);
	TrieSetCell(ConfigMap, "GRENADES_DIVIDER", GRENADES_DIVIDER);

	TrieSetCell(ConfigMap, "GIBS_MODEL", GIBS_MODEL);
	TrieSetCell(ConfigMap, "NULL_MODEL", NULL_MODEL);
	TrieSetCell(ConfigMap, "WORLD_MODEL", WORLD_MODEL);

	TrieSetCell(ConfigMap, "KNIFE_MODEL", WEAPON_KNIFE);
	TrieSetCell(ConfigMap, "HEGRENADE_MODEL", WEAPON_HEGRENADE);
	TrieSetCell(ConfigMap, "FLASHBANG_MODEL", WEAPON_FLASHBANG);
	TrieSetCell(ConfigMap, "SMOKEGRENADE_MODEL", WEAPON_SMOKEGRENADE);
	TrieSetCell(ConfigMap, "DEAGLE_MODEL", WEAPON_DEAGLE);
	TrieSetCell(ConfigMap, "FIVESEVEN_MODEL", WEAPON_FIVESEVEN);
	TrieSetCell(ConfigMap, "GLOCK18_MODEL", WEAPON_GLOCK18);
	TrieSetCell(ConfigMap, "P228_MODEL", WEAPON_P228);
	TrieSetCell(ConfigMap, "USP_MODEL", WEAPON_USP);
}

public ParseConfig() {
	new INIParser:parser = INI_CreateParser();
	INI_SetReaders(parser, "ReadKeyValue", "ReadNewSection");
	INI_ParseFile(parser, CONFIG_FILE_PATH);
	INI_DestroyParser(parser);
}

public PrecacheModels() {
	if(ShieldData[GIBS_MODEL][0] != EOS)
		ShieldGibsCacheId = precache_model(ShieldData[GIBS_MODEL]);

	if(ShieldData[NULL_MODEL][0] != EOS)
		precache_model(ShieldData[NULL_MODEL]);

	if(ShieldData[WORLD_MODEL][0] != EOS)
		precache_model(ShieldData[WORLD_MODEL]);

	for(new i = 1; i < any:WeaponIdType; i++)
		if(ShieldModels[any:i][0] != EOS)
			precache_model(ShieldModels[any:i]);
}

public bool:ReadNewSection(INIParser:parser, const section[], bool:invalidTokens, bool:closeBracket) {	
	if(!closeBracket) {
		log_amx("Closing bracket was not detected! Current section name '%s'.", section);
		return false;
	}

	if(equal(section, "shield")) {
		ParserCurSection = SECTION_SHIELD;
		return true;
	} else if(equal(section, "models")) {
		ParserCurSection = SECTION_MODELS;
		return true;
	}

	return false;
}

public bool:ReadKeyValue(INIParser:parser, const key[], const value[]) {
	new structKey;
	TrieGetCell(ConfigMap, key, structKey);
	
	switch(ParserCurSection) {
		case SECTION_NONE: {
			return false;
		}
		case SECTION_SHIELD: {
			ShieldData[structKey] = any:str_to_float(value);
		}
		case SECTION_MODELS: {
			if(value[0] == EOS)
				return true;

			if(equal(key, "GIBS_MODEL") || equal(key, "NULL_MODEL") || equal(key, "WORLD_MODEL")) {
				copy(ShieldData[any:structKey], MAX_RESOURCE_PATH_LENGTH - 1, value);
			} else {
				copy(ShieldModels[WeaponIdType:structKey], MAX_RESOURCE_PATH_LENGTH - 1, value);
			}
		}
	}

	return true;
}

public plugin_init() {
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHORS);

	RegisterHookChain(RG_CBasePlayer_Killed, "Player_Killed_Post", true);

	RegisterHookChain(RG_CBasePlayerWeapon_DefaultDeploy, "PlayerWeapon_DefaultDeploy_Post", true);

	RegisterHookChain(RG_CBasePlayer_GiveShield, "Player_GiveShield_Pre", false);
	RegisterHookChain(RG_CBasePlayer_DropShield, "Player_DropShield_Post", true);
	
	RegisterHookChain(RG_CBaseEntity_FireBuckshots, "Entity_FireBuckshots_Pre", false);
	RegisterHookChain(RG_CBaseEntity_FireBullets3, "Entity_FireBullets3_Pre", false);

	RegisterHookChain(RG_CBaseEntity_FireBuckshots, "Entity_Fire_Post", true);
	RegisterHookChain(RG_CBaseEntity_FireBullets3, "Entity_Fire_Post", true);

	RegisterHookChain(RG_CGrenade_ExplodeHeGrenade, "Grenade_ExplodeHeGrenade_Pre", false);
	
	HC_PlayerTakeDamage = RegisterHookChain(RG_CBasePlayer_TakeDamage, "Player_TakeDamage_Post", true);
	DisableHookChain(HC_PlayerTakeDamage);
}

/******************************/    MAIN FUNCTIONS    /******************************/

public client_disconnected(playerId) {
	RemovePlayerModelEntity(playerId);

	arrayset(PlayerData[playerId], 0, sizeof(PlayerData[]));
}

public Player_Killed_Post(const victimId) {
	RemovePlayerModelEntity(victimId);
}

public PlayerWeapon_DefaultDeploy_Post(const weaponId) {
	new playerId = get_member(weaponId, m_pPlayer);

	if(!is_user_alive(playerId))
		return;

	if(!bool:get_member(playerId, m_bOwnsShield)) {
		RemovePlayerModelEntity(playerId);
		return;
	}

	SetShieldModel(playerId);
	SetShieldSubModel(PlayerData[playerId][MODEL_ENTITY], PlayerData[playerId][RECEIVED_DAMAGE]);
}

public Player_GiveShield_Pre(const playerId) {
	new shieldId = FindNearestShield(playerId);

	if(is_nullent(shieldId))
		return;

	PlayerData[playerId][RECEIVED_DAMAGE] = GetDmgReceivedToShield(shieldId);
	SetDmgReceivedToShield(shieldId, 0.0);
}

public Player_DropShield_Post(const playerId) {
	RemovePlayerModelEntity(playerId);
	
	new shieldId = FindDroppedShield();
	
	if(is_nullent(shieldId))
		return;

	SetShieldModel(shieldId);
	SetShieldSubModel(shieldId, PlayerData[playerId][RECEIVED_DAMAGE]);

	SetDmgReceivedToShield(shieldId, PlayerData[playerId][RECEIVED_DAMAGE]);
	PlayerData[playerId][RECEIVED_DAMAGE] = 0.0;
}

public Entity_FireBuckshots_Pre(
	entId,
	shots,
	Float:vecSrc[3],
	Float:vecDir[3],
	Float:vecSpread[3],
	Float:distance,
	tracerFreq,
	damage,
	attackerId
) {
	WriteTraceData(attackerId, damage);
}

public Entity_FireBullets3_Pre(
	entId,
	Float:vecSrc[3],
	Float:vecDir[3],
	Float:vecSpread,
	Float:distance,
	penetration,
	bulletType,
	damage,
	Float:rangeModifier,
	attackerId
) {
	WriteTraceData(attackerId, damage);
}

public Entity_Fire_Post() {
	unregister_forward(FM_TraceLine, FWD_TraceLine, true);
}

public Grenade_ExplodeHeGrenade_Pre(const grenadeId) {
	if(is_nullent(grenadeId))
		return;

	new Float:vecGrenadeOrigin[3], Float:grenadeDamage;
	get_entvar(grenadeId, var_origin, vecGrenadeOrigin);
	get_entvar(grenadeId, var_dmg, grenadeDamage);

	ApplyDamageToShieldInRadius(vecGrenadeOrigin, grenadeDamage, grenadeDamage / ShieldData[GRENADES_DIVIDER]);
	
	EnableHookChain(HC_PlayerTakeDamage);
}

public Player_TakeDamage_Post(const victimId, inflictorId, attackerId, Float:damage, bitsDamageType) {
	DisableHookChain(HC_PlayerTakeDamage);
	
	if(~bitsDamageType & DMG_GRENADE)
		return;

	if(!FloatNearlyEqual(damage, 0.0))
		return;
	
	if(!is_user_alive(victimId) || !rg_is_player_can_takedamage(victimId, attackerId))
		return;

	if(!bool:get_member(victimId, m_bOwnsShield))
		return;

	ApplyDamageToPlayerShield(victimId, 0, damage / ShieldData[GRENADES_DIVIDER]);
}

public TraceLine_Post(Float:vecStart[3], Float:vecEnd[3], ignoreMonsters, attackerId, traceLine) {
	if(ApplyDamageToPlayerShield(NULLENT, traceLine, PlayerData[attackerId][FIRED_DAMAGE]))
		return;

	ApplyDamageToShieldOnGround(vecStart, NULLENT, traceLine, PlayerData[attackerId][FIRED_DAMAGE]);
}

/******************************/    STOCK FUNCTIONS    /******************************/

stock WriteTraceData(const attackerId, damage) {
	if(!is_user_alive(attackerId))
		return;
	
	new weaponId = get_member(attackerId, m_pActiveItem);
	
	if(is_nullent(weaponId))
		return;
	
	new bitsWeaponType = (1<<any:get_member(weaponId, m_iId));

	new Float:damageDivider;

	if(CSW_ALL_PISTOLS & bitsWeaponType) {
		damageDivider = ShieldData[PISTOLS_DIVIDER];
	} else if(CSW_ALL_SHOTGUNS & bitsWeaponType) {
		damageDivider = ShieldData[SHOTGUNS_DIVIDER];
	} else if(CSW_ALL_SMGS & bitsWeaponType) {
		damageDivider = ShieldData[SMGS_DIVIDER];
	} else if(CSW_ALL_RIFLES & bitsWeaponType) {
		damageDivider = ShieldData[RIFLES_DIVIDER];
	} else if(CSW_ALL_SNIPERRIFLES & bitsWeaponType) {
		damageDivider = ShieldData[SNIPERRIFLES_DIVIDER];
	} else if(CSW_ALL_MACHINEGUNS & bitsWeaponType) {
		damageDivider = ShieldData[MACHINEGUNS_DIVIDER];
	}

	PlayerData[attackerId][FIRED_DAMAGE] = float(damage) / damageDivider;

	FWD_TraceLine = register_forward(FM_TraceLine, "TraceLine_Post", true);
}

stock ApplyDamageToShieldInRadius(const Float:vecGrenadeOrigin[3], const Float:radius, const Float:damage) {
	new entId = NULLENT;

	while((entId = engfunc(EngFunc_FindEntityInSphere, entId, vecGrenadeOrigin, radius)) > 0) {
		if(!FClassnameIs(entId, "weapon_shield"))
			continue;

		ApplyDamageToShieldOnGround(NULL_VECTOR, entId, 0, damage);
	}
}

stock bool:ApplyDamageToShieldOnGround(const Float:vecStart[3], entId, const traceLine, const Float:damage) {
	if(is_nullent(entId)) {
		new Float:vecEnd2[3];
		get_tr2(traceLine, TR_vecEndPos, vecEnd2);
	
		entId = FindAttackedShieldOnGround(vecStart, vecEnd2);
	}

	if(is_nullent(entId))
		return false;

	new Float:dmgReceived = GetDmgReceivedToShield(entId) + damage;

	if(dmgReceived > ShieldData[STRENGTH]) {
		if(ShieldData[GIBS_MODEL][0] != EOS)
			MakeShieldGibs(entId, ShieldGibsCacheId);

		rg_remove_entity(entId);
	} else {
		SetDmgReceivedToShield(entId, dmgReceived);
		SetShieldSubModel(entId, dmgReceived);
	}

	return true;
}

stock bool:ApplyDamageToPlayerShield(victimId, const traceLine, const Float:damage) {
	if(is_nullent(victimId)) {
		if(HitBoxGroup:get_tr2(traceLine, TR_iHitgroup) != HITGROUP_SHIELD)
			return false;

		victimId = get_tr2(traceLine, TR_pHit);
	}

	if(!is_user_alive(victimId))
		return false;

	PlayerData[victimId][RECEIVED_DAMAGE] += damage;

	if(PlayerData[victimId][RECEIVED_DAMAGE] > ShieldData[STRENGTH]) {
		PlayerData[victimId][RECEIVED_DAMAGE] = 0.0;

		if(ShieldData[GIBS_MODEL][0] != EOS)
			MakeShieldGibs(victimId, ShieldGibsCacheId);
		
		RemovePlayerModelEntity(victimId);
		rg_remove_item(victimId, "weapon_shield");
	} else {
		SetShieldSubModel(PlayerData[victimId][MODEL_ENTITY], PlayerData[victimId][RECEIVED_DAMAGE]);
	}

	return true;
}

stock SetDmgReceivedToShield(const shieldId, const Float:dmgReceived) {
	set_entvar(shieldId, var_dmg_take, FloatNearlyEqual(dmgReceived, 0.0) ? -1.0 : dmgReceived);
}

stock Float:GetDmgReceivedToShield(const shieldId) {
	new Float:dmgReceived = Float:get_entvar(shieldId, var_dmg_take);

	return (dmgReceived == -1.0) ? 0.0 : dmgReceived;
}

stock FindNearestShield(const playerId) {
	new nearestEntId = NULLENT, entId = NULLENT;
	new Float:dist, Float:nearestDist = 8192.0;
	new Float:vecPlOrigin[3], Float:vecEntOrigin[3];
	get_entvar(playerId, var_origin, vecPlOrigin);
	
	while((entId = engfunc(EngFunc_FindEntityByString, entId, "classname", "weapon_shield")) > 0) {
		get_entvar(entId, var_origin, vecEntOrigin);
		dist = get_distance_f(vecPlOrigin, vecEntOrigin);

		if(dist < nearestDist) {
			nearestEntId = entId;
			nearestDist = dist;
		}
	}

	return nearestEntId;
}

stock FindDroppedShield() {
	new entId = NULLENT;
	
	while((entId = engfunc(EngFunc_FindEntityByString, entId, "classname", "weapon_shield")) > 0)
		if(FloatNearlyEqual(Float:get_entvar(entId, var_dmg_take), 0.0))
			break;

	return entId;
}

stock FindAttackedShieldOnGround(const Float:vecStart[3], const Float:vecEnd[3]) {
	new entId = NULLENT;

	while((entId = engfunc(EngFunc_FindEntityByString, entId, "classname", "weapon_shield")) > 0) {
		new traceModel = create_tr2();
		engfunc(EngFunc_TraceModel, vecStart, vecEnd, HULL_POINT, entId, traceModel);

		new hitEnt = get_tr2(traceModel, TR_pHit);
		free_tr2(traceModel);

		if(hitEnt != entId || is_nullent(entId))
			continue;

		return entId;
	}

	return NULLENT;
}

stock SetShieldModel(const entId) {
	if(is_nullent(entId))
		return;
	
	if(entId >= 1 && entId <= MaxClients) {
		new weaponId = get_member(entId, m_pActiveItem);

		if(is_nullent(weaponId))
			return;

		new WeaponIdType:weaponType = WeaponIdType:get_member(weaponId, m_iId);

		if(ShieldModels[weaponType][0] != EOS)
			SetPlayerModel(entId, ShieldModels[weaponType], Float:{0.0, 13.0});
	} else if(ShieldData[WORLD_MODEL] != EOS) {
		engfunc(EngFunc_SetModel, entId, ShieldData[WORLD_MODEL]);
	}
}

stock SetShieldSubModel(const entId, Float:dmgReceived) {	
	if(is_nullent(entId))
		return;
	
	dmgReceived = 100.0 / (ShieldData[STRENGTH] / dmgReceived);
	
	if(dmgReceived > 66.66) {
		set_entvar(entId, var_body, 2);
	} else if(dmgReceived > 33.33) {
		set_entvar(entId, var_body, 1);
	} else if(dmgReceived > 0.0) {
		set_entvar(entId, var_body, 0);
	}
}

stock bool:SetPlayerModel(const playerId, const model[], const Float:attachment[2]) {
	if(is_nullent(PlayerData[playerId][MODEL_ENTITY]))
		if(!CreatePlayerModelEntity(playerId))
			return;

	new entId = PlayerData[playerId][MODEL_ENTITY];

	engfunc(EngFunc_SetModel, entId, model);

	set_entvar(entId, var_frame, 0.0);
	set_entvar(entId, var_framerate, 1.0);
	set_entvar(entId, var_animtime, get_gametime());

	if(ShieldData[NULL_MODEL] != EOS)
		set_entvar(playerId, var_weaponmodel, ShieldData[NULL_MODEL]);

	MoveController(playerId, 0, attachment[0], Float:{-25.0, 25.0});
	MoveController(playerId, 1, attachment[1], Float:{-25.0, 25.0});
}

stock bool:CreatePlayerModelEntity(const playerId) {
	new entId = rg_create_entity("info_target");

	if(!is_nullent(entId)) {
		PlayerData[playerId][MODEL_ENTITY] = entId;

		set_entvar(entId, var_classname, "ent_weapon_pmodel");
		set_entvar(entId, var_movetype, MOVETYPE_FOLLOW);
		set_entvar(entId, var_owner, playerId);
		set_entvar(entId, var_aiment, playerId);

		return true;
	}

	return false;
}

stock RemovePlayerModelEntity(const playerId) {
	new entId = PlayerData[playerId][MODEL_ENTITY];
	PlayerData[playerId][MODEL_ENTITY] = NULLENT;

	if(!is_nullent(entId)) {
		set_entvar(entId, var_flags, FL_KILLME);
		set_entvar(entId, var_nextthink, get_gametime());
	}
}

stock MoveController(const entId, const controller, Float:value, const Float:minMaxValue[2]) {
	if(is_nullent(entId))
		return;

	value = floatclamp(value, minMaxValue[0], minMaxValue[1]);

	new Float:length = floatabs(minMaxValue[0]) + minMaxValue[1];
	value = ((length / 2.0 + value) / length) * 255.0;

	set_entvar(entId, var_controller, floatround(value), controller);
}

stock MakeShieldGibs(const entId, const cacheId) {
	new Float:vecEntOrigin[3];
	get_entvar(entId, var_origin, vecEntOrigin);

	message_begin_f(MSG_PAS, SVC_TEMPENTITY, vecEntOrigin);
	write_byte(TE_BREAKMODEL);
	write_coord_f(vecEntOrigin[0]);
	write_coord_f(vecEntOrigin[1]);
	write_coord_f(vecEntOrigin[2]);
	write_coord(16);
	write_coord(16);
	write_coord(16);
	write_coord(random_num(-50, 50));
	write_coord(random_num(-50, 50));
	write_coord(25);
	write_byte(10);
	write_short(cacheId);
	write_byte(10);
	write_byte(25);
	write_byte(BREAK_METAL);
	message_end();
}

stock bool:FloatNearlyEqual(Float:value1, Float:value2) {
	return bool:((value1 == value2) || (floatabs(value1 - value2) < 0.001));
}