#include <sourcemod>
#include <tf2_stocks>
#include <tf2idb>

#pragma semicolon 1

#define PLUGIN_VERSION		"1.0.0"

////////////////////////
/* Plugin Information */
////////////////////////

public Plugin:myinfo = {
	name = "[TF2] Item Schema Lookup",
	author = "FlaminSarge",
	description = "Provides the item schema lookup commands from TF2ItemsInfo, for TF2 Econ Data",
	version = PLUGIN_VERSION,
	url = "http://github.com/flaminsarge"
};

///////////////////////
/* Defined Constants */
///////////////////////

#define SEARCH_MINLENGTH	2
#define SEARCH_ITEMSPERPAGE	20

#define OLD_MAX_ITEM_ID 31319	//highest as of Oct 12, 2022, "The Pony Express", used if tf2idb fails
#define OLD_MAX_ATTR_ID 3018	//highest as of Sep 10, 2016, "item_drop_wave", used if tf2idb fails

#define ERROR_NONE		0		// PrintToServer only
#define ERROR_LOG		(1<<0)	// use LogToFile
#define ERROR_BREAKF	(1<<1)	// use ThrowError
#define ERROR_BREAKN	(1<<2)	// use ThrowNativeError
#define ERROR_BREAKP	(1<<3)	// use SetFailState
#define ERROR_NOPRINT	(1<<4)	// don't use PrintToServer

#define TF2II_ITEMNAME_LENGTH			64
#define TF2II_ITEMTOOL_LENGTH			16
#define TF2II_ITEMQUALITY_LENGTH		16

#define TF2II_PROP_INVALID				0 // invalid property, not item
// Items only
#define TF2II_PROP_VALIDITEM			(1<<0)
#define TF2II_PROP_BASEITEM				(1<<1)
#define TF2II_PROP_PAINTABLE			(1<<2)
#define TF2II_PROP_UNUSUAL				(1<<3)
#define TF2II_PROP_VINTAGE				(1<<4)
#define TF2II_PROP_STRANGE				(1<<5)
#define TF2II_PROP_HAUNTED				(1<<6)
#define TF2II_PROP_HALLOWEEN			(1<<7) // unused?
#define TF2II_PROP_PROMOITEM			(1<<8)
#define TF2II_PROP_GENUINE				(1<<9)
#define TF2II_PROP_MEDIEVAL				(1<<10)
#define TF2II_PROP_BDAY_STRICT			(1<<11)
#define TF2II_PROP_HOFM_STRICT			(1<<12)	// Halloween Or Full Moon
#define TF2II_PROP_XMAS_STRICT			(1<<13)
#define TF2II_PROP_PROPER_NAME			(1<<14)
// Attributes only
#define TF2II_PROP_VALIDATTRIB			(1<<20)
#define TF2II_PROP_EFFECT_POSITIVE		(1<<21)
#define TF2II_PROP_EFFECT_NEUTRAL		(1<<22)
#define TF2II_PROP_EFFECT_NEGATIVE		(1<<23)
#define TF2II_PROP_HIDDEN				(1<<24)
#define TF2II_PROP_STORED_AS_INTEGER	(1<<25)

#define TF2II_CLASS_NONE				0
#define TF2II_CLASS_SCOUT				(1<<0)
#define TF2II_CLASS_SNIPER				(1<<1)
#define TF2II_CLASS_SOLDIER				(1<<2)
#define TF2II_CLASS_DEMOMAN				(1<<3)
#define TF2II_CLASS_MEDIC				(1<<4)
#define TF2II_CLASS_HEAVY				(1<<5)
#define TF2II_CLASS_PYRO				(1<<6)
#define TF2II_CLASS_SPY					(1<<7)
#define TF2II_CLASS_ENGINEER			(1<<8)
#define TF2II_CLASS_ALL					(0b111111111)
#define TF2II_CLASS_ANY					TF2II_CLASS_ALL

///////////////
/* Enumerics */
///////////////

enum ItemDataType
{
	ItemData_DefinitionID,
	ItemData_Property,
	ItemData_Name,
	ItemData_MLName,
	ItemData_MLSlotName,
	ItemData_MLDescription,
	ItemData_ClassName,
	ItemData_Slot,
	ItemData_ListedSlot,
	ItemData_Tool,
	ItemData_MinLevel,
	ItemData_MaxLevel,
	ItemData_Quality,
	ItemData_UsedBy,
	ItemData_Attributes,
	ItemData_EquipRegions,
	ItemData_LogName,
	ItemData_LogIcon,
	ItemData_KeyValues
};

//////////////////////
/* Global Variables */
//////////////////////

new Handle:sm_tf2isl_version = INVALID_HANDLE;
new Handle:sm_tf2ii_logs = INVALID_HANDLE;
new bool:bUseLogs = true;
new bool:bSchemaLoaded = false;

new Handle:g_hItemProperties = INVALID_HANDLE;


public OnPluginStart()
{
	sm_tf2isl_version = CreateConVar( "sm_tf2isl_version", PLUGIN_VERSION, "TF2 Item Schema Lookup Plugin Version", FCVAR_NOTIFY|FCVAR_REPLICATED|FCVAR_SPONLY );
	SetConVarString( sm_tf2isl_version, PLUGIN_VERSION, true, true );
	HookConVarChange( sm_tf2isl_version, OnConVarChanged_PluginVersion );

	HookConVarChange( sm_tf2ii_logs = CreateConVar( "sm_tf2ii_logs", bUseLogs ? "1" : "0", "Enable/disable logs", 0, true, 0.0, true, 1.0 ), OnConVarChanged );
	decl String:strGameDir[8];
	GetGameFolderName( strGameDir, sizeof(strGameDir) );
	if( !StrEqual( strGameDir, "tf", false ) && !StrEqual( strGameDir, "tf_beta", false ) )
		Error( ERROR_BREAKP|ERROR_LOG, _, "THIS PLUGIN IS FOR TEAM FORTRESS 2 ONLY!" );

	RegConsoleCmd( "sm_si", Command_FindItems, "[TF2II] Find items by name." );
	RegConsoleCmd( "sm_fi", Command_FindItems, "[TF2II] Find items by name." );
	RegConsoleCmd( "sm_sic", Command_FindItemsByClass, "[TF2II] Find items by item class name." );
	RegConsoleCmd( "sm_fic", Command_FindItemsByClass, "[TF2II] Find items by item class name." );
	RegConsoleCmd( "sm_ii", Command_PrintInfo, "[TF2II] Print info about item (by id)." );
	RegConsoleCmd( "sm_pi", Command_PrintInfo, "[TF2II] Print info about item (by id)." );
	RegConsoleCmd( "sm_sa", Command_FindAttributes, "[TF2II] Find attributes by id or name." );
	RegConsoleCmd( "sm_fa", Command_FindAttributes, "[TF2II] Find attributes by id or name." );
	RegConsoleCmd( "sm_sac", Command_FindAttributesByClass, "[TF2II] Find attributes by attribute class name." );
	RegConsoleCmd( "sm_fac", Command_FindAttributesByClass, "[TF2II] Find attributes by attribute class name." );
}

public OnAllPluginsLoaded() {
	if (LibraryExists("tf2idb") && !bSchemaLoaded) {
		bSchemaLoaded = true;
	}
	ReloadConfigs();
}
public OnLibraryAdded(const String:strName[]) {
	if (StrEqual(strName, "tf2idb", false) && !bSchemaLoaded) {
		bSchemaLoaded = true;
	}
}
public OnLibraryRemoved(const String:strName[]) {
	if (StrEqual(strName, "tf2idb", false)) {
		bSchemaLoaded = false;
		Error(ERROR_BREAKP, _, "TF2IDB was unloaded, please reload this plugin");
	}
}

GetConVars()
{
	bUseLogs = GetConVarBool( sm_tf2ii_logs );
}

//////////////////////
/* Command handlers */
//////////////////////
public Action:Command_FindItems( iClient, nArgs )
{
	if( iClient < 0 || iClient > MaxClients )
		return Plugin_Continue;

	decl String:strCmdName[16];
	GetCmdArg( 0, strCmdName, sizeof(strCmdName) );
	if( nArgs < 1 )
	{
		ReplyToCommand( iClient, "Usage: %s <name> [pagenum]", strCmdName );
		return Plugin_Handled;
	}

	new iPage = 0;
	if( nArgs >= 2 )
	{
		decl String:strPage[8];
		GetCmdArg( 2, strPage, sizeof(strPage) );
		if( IsCharNumeric(strPage[0]) )
		{
			iPage = StringToInt( strPage );
			if( iPage < 1 )
				iPage = 1;
		}
	}

	decl String:strSearch[64];
	if( iPage )
		GetCmdArg( 1, strSearch, sizeof(strSearch) );
	else
	{
		iPage = 1;
		GetCmdArgString( strSearch, sizeof(strSearch) );
		StripQuotes( strSearch );
	}
	TrimString( strSearch );
	if( strlen( strSearch ) < SEARCH_MINLENGTH && !IsCharNumeric(strSearch[0]) )
	{
		ReplyToCommand( iClient, "Too short name! Minimum: %d chars", SEARCH_MINLENGTH );
		return Plugin_Handled;
	}


	new maxlen = TF2II_ITEMNAME_LENGTH;

	new Handle:arguments = CreateArray(sizeof(strSearch)+4);
	Format(strSearch, sizeof(strSearch), "%%%s%%", strSearch);
	PushArrayString(arguments, strSearch);
	new DBStatement:resultStatement = TF2IDB_CustomQuery("SELECT id, name FROM tf2idb_item WHERE (name LIKE ?)", arguments, maxlen);
	CloseHandle(arguments);

	new iResults;
	new Handle:hResults = CreateArray(maxlen+1);

	decl String:strItemName[maxlen];

	if (resultStatement != INVALID_HANDLE) {
		while (SQL_FetchRow(resultStatement)) {
			new id = SQL_FetchInt(resultStatement, 0);
			SQL_FetchString(resultStatement, 1, strItemName, maxlen);
			PushArrayCell(hResults, id);
			PushArrayString(hResults, strItemName);
		}
		CloseHandle(resultStatement);
	}

	iResults = GetArraySize( hResults ) / 2;

	ReplyToCommand( iClient, "Found %d items (p. %d/%d):", iResults, ( iResults ? iPage : 0 ), RoundToCeil( float( iResults ) / float(SEARCH_ITEMSPERPAGE) ) );

	iPage--;
	new iMin = SEARCH_ITEMSPERPAGE * iPage;
	iMin = ( iMin < 0 ? 0 : iMin );
	new iMax = SEARCH_ITEMSPERPAGE * (iPage+1);
	iMax = ( iMax >= iResults ? iResults : iMax );

	if( iResults ) {
		for( new i = iMin; i < iMax; i++ )
		{
			GetArrayString( hResults, 2 * i + 1, strItemName, maxlen );
			ReplyToCommand( iClient, "- %d: %s", GetArrayCell( hResults, 2 * i ), strItemName );
		}
	}
	CloseHandle( hResults );

	return Plugin_Handled;
}
public Action:Command_FindItemsByClass( iClient, nArgs )
{
	if( iClient < 0 || iClient > MaxClients )
		return Plugin_Continue;

	decl String:strCmdName[16];
	GetCmdArg( 0, strCmdName, sizeof(strCmdName) );
	if( nArgs < 1 )
	{
		ReplyToCommand( iClient, "Usage: %s <classname> [pagenum]", strCmdName );
		return Plugin_Handled;
	}

	new iPage = 0;
	if( nArgs >= 2 )
	{
		decl String:strPage[8];
		GetCmdArg( 2, strPage, sizeof(strPage) );
		if( IsCharNumeric(strPage[0]) )
		{
			iPage = StringToInt( strPage );
			if( iPage < 1 )
				iPage = 1;
		}
	}

	decl String:strSearch[64];
	if( iPage )
		GetCmdArg( 1, strSearch, sizeof(strSearch) );
	else
	{
		iPage = 1;
		GetCmdArgString( strSearch, sizeof(strSearch) );
		StripQuotes( strSearch );
	}
	TrimString( strSearch );
	if( strlen( strSearch ) < SEARCH_MINLENGTH && !IsCharNumeric(strSearch[0]) )
	{
		ReplyToCommand( iClient, "Too short name! Minimum: %d chars", SEARCH_MINLENGTH );
		return Plugin_Handled;
	}

	new maxlen = TF2II_ITEMNAME_LENGTH;

	new Handle:arguments = CreateArray(sizeof(strSearch)+4);
	Format(strSearch, sizeof(strSearch), "%%%s%%", strSearch);
	PushArrayString(arguments, strSearch);
	new DBStatement:resultStatement = TF2IDB_CustomQuery("SELECT id, name FROM tf2idb_item WHERE (class LIKE ?)", arguments, maxlen);
	CloseHandle(arguments);
	new iResults;

	new Handle:hResults = CreateArray(maxlen+1);

	decl String:strItemName[maxlen];
//	decl String:strItemClass[maxlen];

	if (resultStatement != INVALID_HANDLE) {
		while (SQL_FetchRow(resultStatement)) {
			new id = SQL_FetchInt(resultStatement, 0);
			SQL_FetchString(resultStatement, 1, strItemName, maxlen);
			PushArrayCell(hResults, id);
			PushArrayString(hResults, strItemName);
		}
		CloseHandle(resultStatement);
	}

	iResults = GetArraySize( hResults ) / 2;

	ReplyToCommand( iClient, "Found %d items (p. %d/%d):", iResults, ( iResults ? iPage : 0 ), RoundToCeil( float( iResults ) / float(SEARCH_ITEMSPERPAGE) ) );

	iPage--;
	new iMin = SEARCH_ITEMSPERPAGE * iPage;
	iMin = ( iMin < 0 ? 0 : iMin );
	new iMax = SEARCH_ITEMSPERPAGE * (iPage+1);
	iMax = ( iMax >= iResults ? iResults : iMax );

	if( iResults ) {
		for( new i = iMin; i < iMax; i++ )
		{
			GetArrayString( hResults, 2 * i + 1, strItemName, maxlen );
			ReplyToCommand( iClient, "- %d: %s", GetArrayCell( hResults, 2 * i ), strItemName );
		}
	}
	CloseHandle( hResults );

	return Plugin_Handled;
}
public Action:Command_PrintInfo( iClient, nArgs )
{
	if( iClient < 0 || iClient > MaxClients )
		return Plugin_Continue;

	decl String:strCmdName[16];
	GetCmdArg( 0, strCmdName, sizeof(strCmdName) );
	if( nArgs < 1 )
	{
		if( StrEqual( "sm_pi", strCmdName, false ) )
			ReplyToCommand( iClient, "The Pi number: 3.1415926535897932384626433832795028841971..." );
		else
			ReplyToCommand( iClient, "Usage: %s <id>  [pagenum]", strCmdName );
		return Plugin_Handled;
	}

	decl String:strItemID[32];
	GetCmdArg( 1, strItemID, sizeof(strItemID) );
	new iItemDefID = StringToInt(strItemID);
	if( !ItemHasProp( iItemDefID, TF2II_PROP_VALIDITEM ) )
	{
		ReplyToCommand( iClient, "Item #%d is invalid!", iItemDefID );
		return Plugin_Handled;
	}

	decl String:strMessage[250], String:strBuffer[128];

	ReplyToCommand( iClient, "==================================================" );

	Format( strMessage, sizeof(strMessage), "Item Definition Index: %d", iItemDefID );
	ReplyToCommand( iClient, strMessage );

	ItemData_GetString( iItemDefID, ItemData_Name, strBuffer, sizeof(strBuffer) );
	Format( strMessage, sizeof(strMessage), "Item Name: %s", strBuffer );
	ReplyToCommand( iClient, strMessage );

	ItemData_GetString( iItemDefID, ItemData_ClassName, strBuffer, sizeof(strBuffer) );
	if( strlen( strBuffer ) )
	{
		Format( strMessage, sizeof(strMessage), "Item Class: %s", strBuffer );
		ReplyToCommand( iClient, strMessage );
	}

	ItemData_GetString( iItemDefID, ItemData_Slot, strBuffer, sizeof(strBuffer) );
	if( strlen( strBuffer ) )
	{
		Format( strMessage, sizeof(strMessage), "Item Slot: %s", strBuffer );
		ReplyToCommand( iClient, strMessage );
	}

	ItemData_GetString( iItemDefID, ItemData_ListedSlot, strBuffer, sizeof(strBuffer) );
	if( strlen( strBuffer ) )
	{
		Format( strMessage, sizeof(strMessage), "Listed Item Slot: %s", strBuffer );
		ReplyToCommand( iClient, strMessage );
	}

	Format( strMessage, sizeof(strMessage), "Level bounds: [%d...%d]", ItemData_GetCell( iItemDefID, ItemData_MinLevel ), ItemData_GetCell( iItemDefID, ItemData_MaxLevel ) );
	ReplyToCommand( iClient, strMessage );

	ItemData_GetString( iItemDefID, ItemData_Quality, strBuffer, sizeof(strBuffer) );
	if( strlen(strBuffer) )
	{
		Format( strMessage, sizeof(strMessage), "Quality: %s (%d)", strBuffer, _:GetQualityByName(strBuffer) );
		ReplyToCommand( iClient, strMessage );
	}

	ItemData_GetString( iItemDefID, ItemData_Tool, strBuffer, sizeof(strBuffer) );
	if( strlen(strBuffer) )
	{
		Format( strMessage, sizeof(strMessage), "Tool type: %s", strBuffer );
		ReplyToCommand( iClient, strMessage );
	}

	new bool:bBDAYRestriction = ItemHasProp( iItemDefID, TF2II_PROP_BDAY_STRICT );
	new bool:bHOFMRestriction = ItemHasProp( iItemDefID, TF2II_PROP_HOFM_STRICT );
	new bool:bXMASRestriction = ItemHasProp( iItemDefID, TF2II_PROP_XMAS_STRICT );
	if( bBDAYRestriction || bHOFMRestriction || bXMASRestriction )
		ReplyToCommand( iClient, "Holiday restriction:" );
	if( bBDAYRestriction )
		ReplyToCommand( iClient, "- birthday" );
	if( bHOFMRestriction )
		ReplyToCommand( iClient, "- halloween_or_fullmoon" );
	if( bXMASRestriction )
		ReplyToCommand( iClient, "- christmas" );

	new iUsedByClass = ItemData_GetCell( iItemDefID, ItemData_UsedBy );
	ReplyToCommand( iClient, "Used by classes:" );
	if( iUsedByClass <= TF2II_CLASS_NONE )
		ReplyToCommand( iClient, "- None (%d)", iUsedByClass );
	else if( iUsedByClass == TF2II_CLASS_ALL )
		ReplyToCommand( iClient, "- Any (%d)", iUsedByClass );
	else
	{
		if( iUsedByClass & TF2II_CLASS_SCOUT )
			ReplyToCommand( iClient, "- Scout (%d)", iUsedByClass & TF2II_CLASS_SCOUT );
		if( iUsedByClass & TF2II_CLASS_SNIPER )
			ReplyToCommand( iClient, "- Sniper (%d)", iUsedByClass & TF2II_CLASS_SNIPER );
		if( iUsedByClass & TF2II_CLASS_SOLDIER )
			ReplyToCommand( iClient, "- Soldier (%d)", iUsedByClass & TF2II_CLASS_SOLDIER );
		if( iUsedByClass & TF2II_CLASS_DEMOMAN )
			ReplyToCommand( iClient, "- Demoman (%d)", iUsedByClass & TF2II_CLASS_DEMOMAN );
		if( iUsedByClass & TF2II_CLASS_MEDIC )
			ReplyToCommand( iClient, "- Medic (%d)", iUsedByClass & TF2II_CLASS_MEDIC );
		if( iUsedByClass & TF2II_CLASS_HEAVY )
			ReplyToCommand( iClient, "- Heavy (%d)", iUsedByClass & TF2II_CLASS_HEAVY );
		if( iUsedByClass & TF2II_CLASS_PYRO )
			ReplyToCommand( iClient, "- Pyro (%d)", iUsedByClass & TF2II_CLASS_PYRO );
		if( iUsedByClass & TF2II_CLASS_SPY )
			ReplyToCommand( iClient, "- Spy (%d)", iUsedByClass & TF2II_CLASS_SPY );
		if( iUsedByClass & TF2II_CLASS_ENGINEER )
			ReplyToCommand( iClient, "- Engineer (%d)", iUsedByClass & TF2II_CLASS_ENGINEER );
	}

	new iAttribID, aid[TF2IDB_MAX_ATTRIBUTES], Float:values[TF2IDB_MAX_ATTRIBUTES];
	new count;
	if( (count = TF2IDB_GetItemAttributes(iItemDefID, aid, values)) > 0 )
	{
		ReplyToCommand( iClient, "Attributes:" );
		for( new a = 0; a < count ; a++ )
		{
			iAttribID = aid[a];
			TF2IDB_GetAttributeName( iAttribID, strBuffer, sizeof(strBuffer) );
			Format( strMessage, sizeof(strMessage), "- %s (%d) - %f", strBuffer, iAttribID, values[a] );
			ReplyToCommand( iClient, strMessage );
		}
	}

	if( nArgs >= 2 )
	{
		GetCmdArg( 2, strBuffer, sizeof(strBuffer) );
		if( StringToInt( strBuffer ) > 0 )
		{
			ReplyToCommand( iClient, "=================== EXTRA INFO ===================" );

			ItemData_GetString( iItemDefID, ItemData_MLName, strBuffer, sizeof(strBuffer) );
			if( strlen( strBuffer ) )
			{
				Format( strMessage, sizeof(strMessage), "Item ML Name: %s", strBuffer );
				ReplyToCommand( iClient, strMessage );
			}

			ReplyToCommand( iClient, "Proper name: %s", ItemHasProp( iItemDefID, TF2II_PROP_PROPER_NAME ) ? "true" : "false" );

			ItemData_GetString( iItemDefID, ItemData_LogName, strBuffer, sizeof(strBuffer) );
			if( strlen( strBuffer ) )
			{
				Format( strMessage, sizeof(strMessage), "Kill Log Name: %s", strBuffer );
				ReplyToCommand( iClient, strMessage );
			}

			ItemData_GetString( iItemDefID, ItemData_LogIcon, strBuffer, sizeof(strBuffer) );
			if( strlen( strBuffer ) )
			{
				Format( strMessage, sizeof(strMessage), "Kill Log Icon: %s", strBuffer );
				ReplyToCommand( iClient, strMessage );
			}

			new Handle:hEquipRegions = Handle:ItemData_GetCell( iItemDefID, ItemData_EquipRegions );
			if( hEquipRegions != INVALID_HANDLE )
			{
				ReplyToCommand( iClient, "Equipment regions:" );
				for( new r = 0; r < GetArraySize(hEquipRegions); r++ )
				{
					GetArrayString( hEquipRegions, r, strBuffer, sizeof(strBuffer) );
					Format( strMessage, sizeof(strMessage), "- %s", strBuffer );
					ReplyToCommand( iClient, strMessage );
				}
			}

			new Handle:hKV = Handle:ItemData_GetCell( iItemDefID, ItemData_KeyValues );
			if( hKV != INVALID_HANDLE )
			{
				if( KvJumpToKey( hKV, "model_player_per_class", false ) )
				{
					ReplyToCommand( iClient, "Models per class:" );

					KvGetString( hKV, "scout", strBuffer, sizeof(strBuffer) );
					if( strlen(strBuffer) )
					{
						Format( strMessage, sizeof(strMessage), "- Scout: %s", strBuffer );
						ReplyToCommand( iClient, strMessage );
					}

					KvGetString( hKV, "soldier", strBuffer, sizeof(strBuffer) );
					if( strlen(strBuffer) )
					{
						Format( strMessage, sizeof(strMessage), "- Soldier: %s", strBuffer );
						ReplyToCommand( iClient, strMessage );
					}

					KvGetString( hKV, "sniper", strBuffer, sizeof(strBuffer) );
					if( strlen(strBuffer) )
					{
						Format( strMessage, sizeof(strMessage), "- Sniper: %s", strBuffer );
						ReplyToCommand( iClient, strMessage );
					}

					KvGetString( hKV, "demoman", strBuffer, sizeof(strBuffer) );
					if( strlen(strBuffer) )
					{
						Format( strMessage, sizeof(strMessage), "- Demoman: %s", strBuffer );
						ReplyToCommand( iClient, strMessage );
					}

					KvGetString( hKV, "Medic", strBuffer, sizeof(strBuffer) );
					if( strlen(strBuffer) )
					{
						Format( strMessage, sizeof(strMessage), "- Medic: %s", strBuffer );
						ReplyToCommand( iClient, strMessage );
					}

					KvGetString( hKV, "heavy", strBuffer, sizeof(strBuffer) );
					if( strlen(strBuffer) )
					{
						Format( strMessage, sizeof(strMessage), "- Heavy: %s", strBuffer );
						ReplyToCommand( iClient, strMessage );
					}

					KvGetString( hKV, "pyro", strBuffer, sizeof(strBuffer) );
					if( strlen(strBuffer) )
					{
						Format( strMessage, sizeof(strMessage), "- Pyro: %s", strBuffer );
						ReplyToCommand( iClient, strMessage );
					}

					KvGetString( hKV, "spy", strBuffer, sizeof(strBuffer) );
					if( strlen(strBuffer) )
					{
						Format( strMessage, sizeof(strMessage), "- Spy: %s", strBuffer );
						ReplyToCommand( iClient, strMessage );
					}

					KvGetString( hKV, "engineer", strBuffer, sizeof(strBuffer) );
					if( strlen(strBuffer) )
					{
						Format( strMessage, sizeof(strMessage), "- Engineer: %s", strBuffer );
						ReplyToCommand( iClient, strMessage );
					}

					KvGoBack( hKV );
				}
				else
				{
					KvGetString( hKV, "model_world", strBuffer, sizeof(strBuffer) );
					Format( strMessage, sizeof(strMessage), "World model: %s", strBuffer );
					ReplyToCommand( iClient, strMessage );
				}

				KvGetString( hKV, "model_player", strBuffer, sizeof(strBuffer) );
				Format( strMessage, sizeof(strMessage), "View model: %s", strBuffer );
				ReplyToCommand( iClient, strMessage );

				new nStyles = 1;
				if( KvJumpToKey( hKV, "visuals", false ) && KvJumpToKey( hKV, "styles", false ) && KvGotoFirstSubKey( hKV ) )
				{
					while( KvGotoNextKey( hKV ) )
						nStyles++;
					KvGoBack( hKV );
					KvGoBack( hKV );
					KvGoBack( hKV );
				}
				Format( strMessage, sizeof(strMessage), "Number of styles: %d", nStyles );
				ReplyToCommand( iClient, strMessage );
			}
		}
	}

	ReplyToCommand( iClient, "==================================================" );

	return Plugin_Handled;
}
public Action:Command_FindAttributes( iClient, nArgs )
{
	if( iClient < 0 || iClient > MaxClients )
		return Plugin_Continue;

	decl String:strCmdName[16];
	GetCmdArg( 0, strCmdName, sizeof(strCmdName) );
	if( nArgs < 1 )
	{
		ReplyToCommand( iClient, "Usage: %s <id|name> [pagenum]", strCmdName );
		return Plugin_Handled;
	}

	new iPage = 0;
	if( nArgs >= 2 )
	{
		decl String:strPage[8];
		GetCmdArg( 2, strPage, sizeof(strPage) );
		if( IsCharNumeric(strPage[0]) )
		{
			iPage = StringToInt( strPage );
			if( iPage < 1 )
				iPage = 1;
		}
	}

	decl String:strSearch[64];
	if( iPage )
		GetCmdArg( 1, strSearch, sizeof(strSearch) );
	else
	{
		iPage = 1;
		GetCmdArgString( strSearch, sizeof(strSearch) );
		StripQuotes( strSearch );
	}
	TrimString( strSearch );
	if( strlen( strSearch ) < SEARCH_MINLENGTH && !IsCharNumeric(strSearch[0]) )
	{
		ReplyToCommand( iClient, "Too short name! Minimum: %d chars", SEARCH_MINLENGTH );
		return Plugin_Handled;
	}

	if( IsCharNumeric(strSearch[0]) )
	{
		new iAttribute = StringToInt(strSearch);
		if( !( 0 < iAttribute <= GetMaxAttributeID() ) )
			ReplyToCommand( iClient, "Attribute #%d is out of bounds [1...%d]", iAttribute, GetMaxAttributeID() );

		decl String:strBuffer[128];
		if( !IsValidAttribID( iAttribute ) )
		{
			ReplyToCommand( iClient, "Attribute #%d doesn't exists", iAttribute );
			return Plugin_Handled;
		}

		ReplyToCommand( iClient, "==================================================" );

		ReplyToCommand( iClient, "Attribute Index: %d", iAttribute );

		TF2IDB_GetAttributeName( iAttribute, strBuffer, sizeof(strBuffer) );
		ReplyToCommand( iClient, "Working Name: %s", strBuffer );

		if( TF2IDB_GetAttributeName( iAttribute, strBuffer, sizeof(strBuffer) ) )
			ReplyToCommand( iClient, "Display Name: %s", strBuffer );

		if( TF2IDB_GetAttributeDescString( iAttribute, strBuffer, sizeof(strBuffer) ) )
			ReplyToCommand( iClient, "Description String: %s", strBuffer );

		if( TF2IDB_GetAttributeDescFormat( iAttribute, strBuffer, sizeof(strBuffer) ) )
			ReplyToCommand( iClient, "Description Format: %s", strBuffer );

		if( TF2IDB_GetAttributeClass( iAttribute, strBuffer, sizeof(strBuffer) ) )
			ReplyToCommand( iClient, "Class: %s", strBuffer );

		if( TF2IDB_GetAttributeType( iAttribute, strBuffer, sizeof(strBuffer) ) )
			ReplyToCommand( iClient, "Type: %s", strBuffer );

/*		AttribData_GetString( iAttribute, AttribData_Group, strBuffer, sizeof(strBuffer) );
		if( strlen( strBuffer ) )
			ReplyToCommand( iClient, "Group: %s", strBuffer );
*/

//		ReplyToCommand( iClient, "Bounds of value: [%0.2f...%0.2f]", Float:AttribData_GetCell( iAttribute, AttribData_MinValue ), Float:AttribData_GetCell( iAttribute, AttribData_MaxValue ) );

		if( TF2IDB_GetAttributeEffectType( iAttribute, strBuffer, sizeof(strBuffer) ) )
			ReplyToCommand( iClient, "Effect Type: %s", strBuffer );

		ReplyToCommand( iClient, "Hidden: %s", ( AttribHasProp( iAttribute, TF2II_PROP_HIDDEN ) ? "true" : "false" ) );

		ReplyToCommand( iClient, "As Integer: %s", ( AttribHasProp( iAttribute, TF2II_PROP_STORED_AS_INTEGER ) ? "true" : "false" ) );

		ReplyToCommand( iClient, "==================================================" );

		return Plugin_Handled;
	}

	new maxlen = TF2IDB_ATTRIBNAME_LENGTH;

	new Handle:arguments = CreateArray(sizeof(strSearch)+4);
	Format(strSearch, sizeof(strSearch), "%%%s%%", strSearch);
	PushArrayString(arguments, strSearch);
	new DBStatement:resultStatement = TF2IDB_CustomQuery("SELECT id, name FROM tf2idb_attributes WHERE (name LIKE ?)", arguments, maxlen);
	CloseHandle(arguments);
	new iResults;
	new Handle:hResults = CreateArray(maxlen+1);

	decl String:strAttribName[maxlen];

	if (resultStatement != INVALID_HANDLE) {
		while (SQL_FetchRow(resultStatement)) {
			new id = SQL_FetchInt(resultStatement, 0);
			SQL_FetchString(resultStatement, 1, strAttribName, maxlen);
			PushArrayCell(hResults, id);
			PushArrayString(hResults, strAttribName);
		}
		CloseHandle(resultStatement);
	}

	iResults = GetArraySize(hResults) / 2;

	ReplyToCommand( iClient, "Found %d attributes (p. %d/%d):", iResults, ( iResults ? iPage : 0 ), RoundToCeil( float( iResults ) / float(SEARCH_ITEMSPERPAGE) ) );

	iPage--;
	new iMin = SEARCH_ITEMSPERPAGE * iPage;
	iMin = ( iMin < 0 ? 0 : iMin );
	new iMax = SEARCH_ITEMSPERPAGE * (iPage+1);
	iMax = ( iMax >= iResults ? iResults : iMax );

	if (iResults) {
		for (new i = iMin; i < iMax; i++) {
			GetArrayString(hResults, 2*i+1, strAttribName, maxlen);
			ReplyToCommand( iClient, "- %d: %s", GetArrayCell(hResults, 2*i), strAttribName );
		}
	}
	CloseHandle(hResults);

	return Plugin_Handled;
}
public Action:Command_FindAttributesByClass( iClient, nArgs )
{
	if( iClient < 0 || iClient > MaxClients )
		return Plugin_Continue;

	decl String:strCmdName[16];
	GetCmdArg( 0, strCmdName, sizeof(strCmdName) );
	if( nArgs < 1 )
	{
		ReplyToCommand( iClient, "Usage: %s <name> [pagenum]", strCmdName );
		return Plugin_Handled;
	}

	new iPage = 0;
	if( nArgs >= 2 )
	{
		decl String:strPage[8];
		GetCmdArg( 2, strPage, sizeof(strPage) );
		if( IsCharNumeric(strPage[0]) )
		{
			iPage = StringToInt( strPage );
			if( iPage < 1 )
				iPage = 1;
		}
	}

	decl String:strSearch[64];
	if( iPage )
		GetCmdArg( 1, strSearch, sizeof(strSearch) );
	else
	{
		iPage = 1;
		GetCmdArgString( strSearch, sizeof(strSearch) );
		StripQuotes( strSearch );
	}
	TrimString( strSearch );
	if( strlen( strSearch ) < SEARCH_MINLENGTH && !IsCharNumeric(strSearch[0]) )
	{
		ReplyToCommand( iClient, "Too short name! Minimum: %d chars", SEARCH_MINLENGTH );
		return Plugin_Handled;
	}
	new maxlen = TF2IDB_ATTRIBCLASS_LENGTH;

	new Handle:arguments = CreateArray(sizeof(strSearch)+4);
	Format(strSearch, sizeof(strSearch), "%%%s%%", strSearch);
	PushArrayString(arguments, strSearch);
	new DBStatement:resultStatement = TF2IDB_CustomQuery("SELECT id, name, attribute_class FROM tf2idb_attributes WHERE (attribute_class LIKE ?)", arguments, maxlen);
	CloseHandle(arguments);
	new iResults;
	new Handle:hResults = CreateArray(maxlen+1);

	decl String:strAttribName[maxlen];
	decl String:strAttribClass[maxlen];

	if (resultStatement != INVALID_HANDLE) {
		while (SQL_FetchRow(resultStatement)) {
			new id = SQL_FetchInt(resultStatement, 0);
			SQL_FetchString(resultStatement, 1, strAttribName, maxlen);
			SQL_FetchString(resultStatement, 2, strAttribClass, maxlen);
			PushArrayCell(hResults, id);
			PushArrayString(hResults, strAttribName);
			PushArrayString(hResults, strAttribClass);
		}
		CloseHandle(resultStatement);
	}

	ReplyToCommand( iClient, "Found %d attributes (p. %d/%d):", iResults, ( iResults ? iPage : 0 ), RoundToCeil( float( iResults ) / float(SEARCH_ITEMSPERPAGE) ) );

	iPage--;
	new iMin = SEARCH_ITEMSPERPAGE * iPage;
	iMin = ( iMin < 0 ? 0 : iMin );
	new iMax = SEARCH_ITEMSPERPAGE * (iPage+1);
	iMax = ( iMax >= iResults ? iResults : iMax );

	if (iResults) {
		for (new i = iMin; i < iMax; i++) {
			GetArrayString(hResults, 3*i+1, strAttribName, maxlen);
			GetArrayString(hResults, 3*i+2, strAttribClass, maxlen);
			ReplyToCommand( iClient, "- %d: %s (%s)", GetArrayCell(hResults, 3*i), strAttribName, strAttribClass );
		}
	}
	CloseHandle( hResults );

	return Plugin_Handled;
}

///////////////////
/* CVar handlers */
///////////////////

public OnConVarChanged_PluginVersion( Handle:hConVar, const String:strOldValue[], const String:strNewValue[] ) {
	if( strcmp( strNewValue, PLUGIN_VERSION, false ) != 0 ) {
		SetConVarString( hConVar, PLUGIN_VERSION, true, true );
	}
}
public OnConVarChanged( Handle:hConVar, const String:strOldValue[], const String:strNewValue[] ) {
	GetConVars();
}

///////////////////////
/* Private functions */
///////////////////////

stock ReloadConfigs()
{
	decl String:strBuffer[128];

	new Handle:hItemConfig = CreateKeyValues("items_config");

	decl String:strFilePath[PLATFORM_MAX_PATH] = "data/tf2itemsinfo.txt";
	BuildPath( Path_SM, strFilePath, sizeof(strFilePath), strFilePath );
	if( !FileExists( strFilePath ) ) {
		Error( ERROR_LOG, _, "Missing config file, making empty at %s", strFilePath );
		KeyValuesToFile( hItemConfig, strFilePath );
		CloseHandle( hItemConfig );
		return;
	}
	if (g_hItemProperties == INVALID_HANDLE) {
		g_hItemProperties = CreateTrie();
	}

	FileToKeyValues( hItemConfig, strFilePath );
	KvRewind( hItemConfig );

	if( KvGotoFirstSubKey( hItemConfig ) ) {
		new iItemDefID, iProperty;
		do {
			KvGetSectionName( hItemConfig, strBuffer, sizeof(strBuffer) );
			if (!IsCharNumeric(strBuffer[0])) {
				continue;
			}
			iItemDefID = StringToInt( strBuffer );
			if (!( 0 <= iItemDefID <= GetMaxItemID())) {
				continue;
			}

			iProperty = ItemProperties_Get( iItemDefID );
			if( KvGetNum( hItemConfig, "unusual", 0 ) )
				iProperty |= TF2II_PROP_UNUSUAL;
			if( KvGetNum( hItemConfig, "vintage", 0 ) )
				iProperty |= TF2II_PROP_VINTAGE;
			if( KvGetNum( hItemConfig, "strange", 0 ) )
				iProperty |= TF2II_PROP_STRANGE;
			if( KvGetNum( hItemConfig, "haunted", 0 ) )
				iProperty |= TF2II_PROP_HAUNTED;
			if( KvGetNum( hItemConfig, "halloween", 0 ) )
				iProperty |= TF2II_PROP_HALLOWEEN;
			if( KvGetNum( hItemConfig, "promotional", 0 ) )
				iProperty |= TF2II_PROP_PROMOITEM;
			if( KvGetNum( hItemConfig, "genuine", 0 ) )
				iProperty |= TF2II_PROP_GENUINE;
			if( KvGetNum( hItemConfig, "medieval", 0 ) )
				iProperty |= TF2II_PROP_MEDIEVAL;
			ItemProperties_Set( iItemDefID, iProperty );
		}
		while( KvGotoNextKey( hItemConfig ) );
	}

	CloseHandle( hItemConfig );

	Error( ERROR_NONE, _, "Item config loaded." );
}

TF2ItemQuality:GetQualityByName( const String:strSearch[] ) {
	return TF2IDB_GetQualityByName(strSearch);
}

stock bool:GetToolType(iItemDefID, String:strBuffer[], iBufferLength) {
	decl String:strId[16];
	new Handle:arguments = CreateArray(16);
	IntToString(iItemDefID, strId, sizeof(strId));
	PushArrayString(arguments, strId);
	new DBStatement:resultStatement = TF2IDB_CustomQuery("SELECT tool_type FROM tf2idb_item WHERE id=?", arguments, iBufferLength);
	CloseHandle(arguments);
	if (resultStatement == INVALID_HANDLE) {
		return false;
	}
	if (SQL_FetchRow(resultStatement)) {
		SQL_FetchString(resultStatement, 0, strBuffer, iBufferLength);
		CloseHandle(resultStatement);
		return true;
	}
	CloseHandle(resultStatement);
	return false;
}
stock Handle:Internal_FindItems(Handle:hPlugin, String:strClass[], String:strSlot[], iUsedByClass, String:strTool[])
{
	char classes[9][32] = {"scout", "sniper", "soldier", "demoman", "medic", "heavy", "pyro", "spy", "engineer"};
	int paramCount = 0;
	if (strClass[0])
	{
		paramCount++;
	}
	if (strSlot[0])
	{
		paramCount++;
	}
	if (strTool[0])
	{
		paramCount++;
	}

	char query[512];
	strcopy(query, sizeof(query), "SELECT a.id FROM tf2idb_item a");
	if (iUsedByClass)
	{
		StrCat(query, sizeof(query), " JOIN tf2idb_class b ON a.id=b.id WHERE (0");
		for (int i = 0; i < 9; i++)
		{
			if (!(iUsedByClass & (1 << i))) continue;
			Format(query, sizeof(query), "%s OR b.class='%s'", query, classes[i]);
		}
		StrCat(query, sizeof(query), ")");
		if (paramCount)
		{
			StrCat(query, sizeof(query), " AND");
		}
	}
	else
	{
		if (paramCount)
		{
			StrCat(query, sizeof(query), " WHERE");
		}
	}
	if (strClass[0])
	{
		Format(query, sizeof(query), "%s a.class='%s'", query, strClass);
		paramCount--;
		if (paramCount > 0)
			StrCat(query, sizeof(query), " AND");
	}
	if (strSlot[0])
	{
		Format(query, sizeof(query), "%s a.slot='%s'", query, strSlot);
		paramCount--;
		if (paramCount > 0)
			StrCat(query, sizeof(query), " AND");
	}
	if (strTool[0])
	{
		Format(query, sizeof(query), "%s a.tool_type='%s'", query, strTool);
		paramCount--;
//		if (paramCount > 0)
//			StrCat(query, sizeof(query), " AND");
	}

	new Handle:hResults = TF2IDB_FindItemCustom(query);

	new Handle:ret = CloneHandle(hResults, hPlugin);
	CloseHandle(hResults);
	return ret;
}

//////////////////
/* SQL handlers */
//////////////////

public SQL_ErrorCheck( Handle:hOwner, Handle:hQuery, const String:strError[], any:iUnused ) {
	if( strlen( strError ) ) {
		LogError( "MySQL DB error: %s", strError );
	}
}
/////////////////////
/* Stock functions */
/////////////////////

stock Error( iFlags = ERROR_NONE, iNativeErrCode = SP_ERROR_NONE, const String:strMessage[], any:... )
{
	decl String:strBuffer[1024];
	VFormat( strBuffer, sizeof(strBuffer), strMessage, 4 );

	if( iFlags )
	{
		if( (iFlags & ERROR_LOG) && bUseLogs )
		{
			decl String:strFile[PLATFORM_MAX_PATH];
			FormatTime( strFile, sizeof(strFile), "%Y%m%d" );
			Format( strFile, sizeof(strFile), "TF2II%s", strFile );
			BuildPath( Path_SM, strFile, sizeof(strFile), "logs/%s.log", strFile );
			LogToFileEx( strFile, strBuffer );
		}

		if( iFlags & ERROR_BREAKF )
			ThrowError( strBuffer );
		if( iFlags & ERROR_BREAKN )
			ThrowNativeError( iNativeErrCode, strBuffer );
		if( iFlags & ERROR_BREAKP )
			SetFailState( strBuffer );

		if( iFlags & ERROR_NOPRINT )
			return;
	}

	PrintToServer( "[TF2ItemsInfo] %s", strBuffer );
}

//////////////////////////
/* ItemData_* functions */
//////////////////////////

stock any:ItemData_GetCell( iItemDefID, ItemDataType:iIDType )
{
	int minLevel, maxLevel;
	if (iIDType == ItemData_MinLevel || iIDType == ItemData_MaxLevel) {
		TF2IDB_GetItemLevels(iItemDefID, minLevel, maxLevel);
	}
	switch (iIDType) {
		case ItemData_DefinitionID: return iItemDefID;
		case ItemData_MinLevel: return minLevel;
		case ItemData_MaxLevel: return maxLevel;
		case ItemData_UsedBy: return TF2IDB_UsedByClasses(iItemDefID) >> 1;
		case ItemData_EquipRegions: return TF2IDB_GetItemEquipRegions(iItemDefID);
		case ItemData_KeyValues: return INVALID_HANDLE;
		default: return 0;
	}
}


stock ItemData_GetString( iItemDefID, ItemDataType:iIDType, String:strValue[], iValueLength )
{
	switch (iIDType) {
		case ItemData_Name: TF2IDB_GetItemName(iItemDefID, strValue, iValueLength);
		case ItemData_ClassName: TF2IDB_GetItemClass(iItemDefID, strValue, iValueLength);
		case ItemData_Slot: TF2IDB_GetItemSlotName(iItemDefID, strValue, iValueLength);
		case ItemData_ListedSlot: TF2IDB_GetItemSlotName(iItemDefID, strValue, iValueLength);
		case ItemData_Tool: GetToolType(iItemDefID, strValue, iValueLength);
		case ItemData_Quality: TF2IDB_GetItemQualityName(iItemDefID, strValue, iValueLength);
		case ItemData_MLName: GetItemMLName(iItemDefID, strValue, iValueLength);
		default: strcopy(strValue, iValueLength, "");
	}
	return strlen(strValue);
}
stock bool:GetItemMLName(iItemDefID, String:strBuffer[], iBufferLength) {
	decl String:strId[16];
	new Handle:arguments = CreateArray(16);
	IntToString(iItemDefID, strId, sizeof(strId));
	PushArrayString(arguments, strId);
	new DBStatement:resultStatement = TF2IDB_CustomQuery("SELECT item_name FROM tf2idb_item WHERE id=?", arguments, iBufferLength);
	CloseHandle(arguments);
	if (resultStatement == INVALID_HANDLE) {
		return false;
	}
	if (SQL_FetchRow(resultStatement)) {
		SQL_FetchString(resultStatement, 0, strBuffer, iBufferLength);
		CloseHandle(resultStatement);
		return true;
	}
	CloseHandle(resultStatement);
	return false;
}

//////////////////////////
/* Validating functions */
//////////////////////////

stock bool:IsValidItemID( iItemDefID ) {
	return ( 0 <= iItemDefID <= GetMaxItemID() && TF2IDB_IsValidItemID(iItemDefID) );
}
stock bool:IsValidAttribID( iAttribID ) {
	return ( 0 < iAttribID <= GetMaxAttributeID() && TF2IDB_IsValidAttributeID(iAttribID) );
}

stock int GetMaxItemID() {
	static bool found = false;
	static int maxVal = 0;
	if (!bSchemaLoaded) {
		return OLD_MAX_ITEM_ID;
	}
	if (!found) {
		new Handle:list = TF2IDB_FindItemCustom("SELECT MAX(id) FROM tf2idb_item");
		maxVal = GetArrayCell(list, 0);
		CloseHandle(list);
		found = true;
	}
	return maxVal;
}

stock int GetMaxAttributeID() {
	static bool found = false;
	static int maxVal = 0;
	if (!bSchemaLoaded) {
		return OLD_MAX_ATTR_ID;
	}
	if (!found) {
		new Handle:list = TF2IDB_FindItemCustom("SELECT MAX(id) FROM tf2idb_attributes");
		maxVal = GetArrayCell(list, 0);
		CloseHandle(list);
		found = true;
	}
	return maxVal;
}
/*
#define TF2II_PROP_UNUSUAL				(1<<3)
#define TF2II_PROP_VINTAGE				(1<<4)
#define TF2II_PROP_STRANGE				(1<<5)
#define TF2II_PROP_HAUNTED				(1<<6)
#define TF2II_PROP_HALLOWEEN			(1<<7) // unused?
#define TF2II_PROP_PROMOITEM			(1<<8)
#define TF2II_PROP_GENUINE				(1<<9)
*/
stock bool:ItemHasProp( iItemDefID, iFlags )
{
	if( iFlags <= TF2II_PROP_INVALID )
		return false;
	return ( ItemProperties_Get(iItemDefID) & iFlags ) == iFlags;
}

stock ItemProperties_GetBase(iItemDefID) {
	if( !( 0 <= iItemDefID <= GetMaxItemID() ))
		return 0;
	if( !IsValidItemID( iItemDefID ) )
		return 0;
	new resultFlags = TF2II_PROP_VALIDITEM;
	resultFlags |= (TF2II_IsBaseItem(iItemDefID) ? TF2II_PROP_BASEITEM : 0);
	resultFlags |= (TF2II_IsItemPaintable(iItemDefID) ? TF2II_PROP_PAINTABLE : 0);
	resultFlags |= (TF2II_IsHalloweenItem(iItemDefID) ? TF2II_PROP_HALLOWEEN : 0);
	resultFlags |= (TF2II_IsMedievalWeapon(iItemDefID) ? TF2II_PROP_MEDIEVAL : 0);
	resultFlags |= (TF2II_IsBirthdayItem(iItemDefID) ? TF2II_PROP_BDAY_STRICT : 0);
	resultFlags |= (TF2II_IsHalloweenOrFullMoonItem(iItemDefID) ? TF2II_PROP_HOFM_STRICT : 0);
	resultFlags |= (TF2II_IsChristmasItem(iItemDefID) ? TF2II_PROP_XMAS_STRICT : 0);
	resultFlags |= (TF2II_HasProperName(iItemDefID) ? TF2II_PROP_PROPER_NAME : 0);
	return resultFlags;
}
stock ItemProperties_Get(iItemDefID) {
	new val = 0;
	new String:strId[16];
	IntToString(iItemDefID, strId, sizeof(strId));
	if (!GetTrieValue(g_hItemProperties, strId, val)) {
		val = 0;
	}
	return val | ItemProperties_GetBase(iItemDefID);
}
stock ItemProperties_Set(iItemDefID, iProperties) {
	new String:strId[16];
	IntToString(iItemDefID, strId, sizeof(strId));
	SetTrieValue(g_hItemProperties, strId, iProperties);
}

stock bool:AttribHasProp( iAttribID, iFlags )
{
	new hidden, stored_as_integer;
	new resultFlags;
	char effect_type[32];
	bool exists = TF2IDB_GetAttributeProperties(iAttribID, hidden, stored_as_integer, _, _, _);
	if( !( 0 < iAttribID <= GetMaxAttributeID() ) || iFlags <= TF2II_PROP_INVALID )
		return false;
	if (!exists) {
		return false;
	}
	resultFlags |= TF2II_PROP_VALIDATTRIB;
	resultFlags |= (hidden == 1 ? TF2II_PROP_HIDDEN : 0);
	resultFlags |= (stored_as_integer == 1 ? TF2II_PROP_STORED_AS_INTEGER : 0);
	TF2IDB_GetAttributeEffectType(iAttribID, effect_type, sizeof(effect_type));
	resultFlags |= (StrEqual(effect_type, "positive") ? TF2II_PROP_EFFECT_POSITIVE : 0);
	resultFlags |= (StrEqual(effect_type, "neutral") ? TF2II_PROP_EFFECT_NEUTRAL : 0);
	resultFlags |= (StrEqual(effect_type, "negative") ? TF2II_PROP_EFFECT_NEGATIVE : 0);

	return ( resultFlags & iFlags ) == iFlags;
}

stock bool:IsValidClient( _:iClient )
{
	if( iClient <= 0 || iClient > MaxClients ) return false;
	if( !IsClientConnected(iClient) || !IsClientInGame(iClient) ) return false;
#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 4
	if( IsClientSourceTV(iClient) || IsClientReplay(iClient) ) return false;
#endif
	return true;
}

stock bool:TF2II_IsBaseItem( iItemDefinitionIndex )
{
	new String:query[128];
	FormatEx(query, sizeof(query), "SELECT baseitem FROM tf2idb_item WHERE id='%d'", iItemDefinitionIndex);
	new Handle:result = TF2IDB_FindItemCustom(query);
	if (result == INVALID_HANDLE)
		return false;
	new size = GetArraySize(result);
	new val = size > 0 ? GetArrayCell(result, 0) : 0;
	CloseHandle(result);
	return !!val;
}
stock bool:TF2II_IsItemPaintable( iItemDefinitionIndex )
{
	new String:query[128];
	FormatEx(query, sizeof(query), "SELECT id FROM tf2idb_capabilities WHERE capability='paintable' AND id='%d'", iItemDefinitionIndex);
	new Handle:result = TF2IDB_FindItemCustom(query);
	if (result == INVALID_HANDLE)
		return false;
	new size = GetArraySize(result);
	CloseHandle(result);
	return size > 0;
}
stock bool:TF2II_ItemCanBeUnusual( iItemDefinitionIndex )
{
	return ItemHasProp( iItemDefinitionIndex, TF2II_PROP_UNUSUAL );
}
stock bool:TF2II_ItemCanBeVintage( iItemDefinitionIndex )
{
	return ItemHasProp( iItemDefinitionIndex, TF2II_PROP_VINTAGE );
}
stock bool:TF2II_IsHauntedItem( iItemDefinitionIndex )
{
	return ItemHasProp( iItemDefinitionIndex, TF2II_PROP_HAUNTED );
}
stock bool:TF2II_IsHalloweenItem( iItemDefinitionIndex )
{
	new String:query[128];
	FormatEx(query, sizeof(query), "SELECT id FROM tf2idb_item WHERE holiday_restriction LIKE 'halloween%' AND id='%d'", iItemDefinitionIndex);
	new Handle:result = TF2IDB_FindItemCustom(query);
	if (result == INVALID_HANDLE)
		return false;
	new size = GetArraySize(result);
	CloseHandle(result);
	return size > 0;
}
stock bool:TF2II_IsHalloweenOrFullMoonItem( iItemDefinitionIndex )
{
	new String:query[128];
	FormatEx(query, sizeof(query), "SELECT id FROM tf2idb_item WHERE holiday_restriction='halloween_or_fullmoon' AND id='%d'", iItemDefinitionIndex);
	new Handle:result = TF2IDB_FindItemCustom(query);
	if (result == INVALID_HANDLE)
		return false;
	new size = GetArraySize(result);
	CloseHandle(result);
	return size > 0;
}
stock bool:TF2II_IsBirthdayItem( iItemDefinitionIndex )
{
	new String:query[128];
	FormatEx(query, sizeof(query), "SELECT id FROM tf2idb_item WHERE holiday_restriction='birthday' AND id='%d'", iItemDefinitionIndex);
	new Handle:result = TF2IDB_FindItemCustom(query);
	if (result == INVALID_HANDLE)
		return false;
	new size = GetArraySize(result);
	CloseHandle(result);
	return size > 0;
}
stock bool:TF2II_IsChristmasItem( iItemDefinitionIndex )
{
	new String:query[128];
	FormatEx(query, sizeof(query), "SELECT id FROM tf2idb_item WHERE holiday_restriction='christmas' AND id='%d'", iItemDefinitionIndex);
	new Handle:result = TF2IDB_FindItemCustom(query);
	if (result == INVALID_HANDLE)
		return false;
	new size = GetArraySize(result);
	CloseHandle(result);
	return size > 0;
}
stock bool:TF2II_HasProperName( iItemDefinitionIndex )
{
	new String:query[128];
	FormatEx(query, sizeof(query), "SELECT id FROM tf2idb_item WHERE propername=1 AND id='%d'", iItemDefinitionIndex);
	new Handle:result = TF2IDB_FindItemCustom(query);
	if (result == INVALID_HANDLE)
		return false;
	new size = GetArraySize(result);
	CloseHandle(result);
	return size > 0;
}
stock bool:TF2II_IsMedievalWeapon( iItemDefinitionIndex )
{
	return TF2IDB_ItemHasAttribute(iItemDefinitionIndex, 2029); //'allowed in medieval mode'
}
stock bool:TF2II_ItemCanBeStrange( iItemDefinitionIndex )
{
	return ItemHasProp( iItemDefinitionIndex, TF2II_PROP_STRANGE );
}
