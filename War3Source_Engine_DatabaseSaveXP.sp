

#include <sourcemod>
#include "W3SIncs/War3Source_Interface"









new Handle:DBIDB;
//new Handle:vecLevelConfiguration;
new String:sCachedDBIName[256];
new String:dbErrorMsg[512];

new War3SQLType:g_SQLType; 

// ConVar definitions
new Handle:m_SaveXPConVar;
new Handle:hSetRaceOnJoinCvar;

new Handle:m_AutosaveTime;
new Handle:hCvarPrintOnSave;

new Handle:g_OnWar3PlayerAuthedHandle;
new desiredRaceOnJoin[MAXPLAYERS];

public Plugin:myinfo= 
{
	name="War3Source Engine Database save xp",
	author="Ownz (DarkEnergy)",
	description="War3Source Core Plugins",
	version="1.0",
	url="http://war3source.com/"
};


public bool:InitNativesForwards()
{
	if(W3()){
		PrintToServer("W3 MODE");
		CreateNative("W3SaveXP" ,NW3SaveXP)
		CreateNative("W3SaveEnabled" ,NW3SaveEnabled)
		CreateNative("W3GetDBHandle" ,NW3GetDBHandle)
	}
	return true;
}

public OnPluginStart()
{
	if(W3()){
		m_SaveXPConVar=CreateConVar("war3_savexp","1");
		W3SetVar(hSaveEnabledCvar,m_SaveXPConVar);
			
		hSetRaceOnJoinCvar=CreateConVar("war3_set_race_on_join","1");
	
		m_AutosaveTime=CreateConVar("war3_autosavetime","60");
		hCvarPrintOnSave=CreateConVar("war3_print_on_autosave","0","Print a message to chat when xp is auto saved?");
	
		g_OnWar3PlayerAuthedHandle=CreateGlobalForward("OnWar3PlayerAuthed",ET_Ignore,Param_Cell,Param_Cell);
	
		
		ConnectDB();
		
		CreateTimer(GetConVarFloat(m_AutosaveTime),DoAutosave);
	}
	
}
public OnMapStart(){
	
}

public OnPluginEnd(){
	//sm bug? may not get called
}

public OnAllPluginsLoaded() //called once only, will not call again when map changes
{
	if(DBIDB&&W3())
		War3Source_SQLTable();
}

public NW3SaveXP(Handle:plugin,numParams)
{
	new client=GetNativeCell(1);
	new race=GetNativeCell(2);
	War3Source_SavePlayerData(client,race) //saves main also
}
public NW3SaveEnabled(Handle:plugin,numParams)
{
	return GetConVarInt(m_SaveXPConVar);
}
public NW3GetDBHandle(Handle:plugin,numParams)
{
	return _:DBIDB;
}















ConnectDB(){

	new Handle:keyValue=CreateKeyValues("War3SourceSettings");
	decl String:path[1024];
	BuildPath(Path_SM,path,sizeof(path),"configs/war3source.ini");
	FileToKeyValues(keyValue,path);
	// Load level configuration
	KvRewind(keyValue);
	new String:database_connect[256];
	KvGetString(keyValue,"database",database_connect,sizeof(database_connect),"default");
	decl String:error[256];
	strcopy(sCachedDBIName,256,database_connect);
	
	
	if(StrEqual(database_connect,"",false) || StrEqual(database_connect,"default",false))
	{
		DBIDB=SQL_DefConnect(error,sizeof(error));	///use default connect, returns a handle...
	}
	else
	{
		DBIDB=SQL_Connect(database_connect,true,error,sizeof(error));
	}
	if(!DBIDB)
	{
		LogError("[War3Source] ERROR: DBIDB invalid handle, Check SourceMod database config, could not connect. ");
		Format(dbErrorMsg,sizeof(dbErrorMsg),"ERR: Could not connect to DB. \n%s",error);
		LogError("ERRMSG:(%s)",error);
	}
	else
	{
		
		new String:driver_ident[64];
		SQL_ReadDriver(DBIDB,driver_ident,sizeof(driver_ident));
		if(StrEqual(driver_ident,"mysql",false))
		{
			g_SQLType=SQLType_MySQL;
		}
		else if(StrEqual(driver_ident,"sqlite",false))
		{
			g_SQLType=SQLType_SQLite;
		}
		else
		{
			g_SQLType=SQLType_Unknown;
		}
		PrintToServer("[War3Source] SQL connection successful, driver %s",driver_ident);
		
		W3SetVar(hDatabase,DBIDB);
		W3SetVar(hDatabaseType,g_SQLType);
	}
	return true;
}

public Action:DoAutosave(Handle:timer,any:data)
{
	if(W3SaveEnabled())
	{
		for(new x=1;x<=MaxClients;x++)
		{
			if(ValidPlayer(x)&& W3IsPlayerXPLoaded(x))
			{
				War3Source_SavePlayerData(x,War3_GetRace(x));
			}
		}
		if(GetConVarInt(hCvarPrintOnSave)>0){
			War3_ChatMessage(0,"%t","Saving all player XP and updating stats");
		}
		
	}
	CreateTimer(GetConVarFloat(m_AutosaveTime),DoAutosave);
}



stock AddColumn(Handle:DB,const String:columnname[],const String:datatype[],const String:table_name[])
{
	decl String:query[256];
	Format(query,sizeof(query),"ALTER TABLE %s ADD COLUMN %s %s DEFAULT '0'",table_name,columnname,datatype);
	//SQL_TQuery(DB,  SQLWar3GeneralCallback,query);//
	SQL_FastQueryLogOnError(DB,query);
	
}

W3SQLPlayerInt(Handle:query,const String:columnname[]) //fech from query
{
	new column;
	SQL_FieldNameToNum(query,columnname,column);
	decl String:result[16];
	SQL_FetchString(query,column,result,sizeof(result));
	return StringToInt(result);
}

W3SQLPlayerString(Handle:query,const String:columnname[],String:out_buffer[],size_out) //fech from query
{
	new column;
	if(SQL_FieldNameToNum(query,columnname,column))
	{
		SQL_FetchString(query,column,out_buffer,size_out);
		return true;
	}
	return false;
}



War3Source_SQLTable()
{
	PrintToServer("War3Source_SQLTable war3source table check handling");
	if(DBIDB!=INVALID_HANDLE)
	{
		// Check if the table exists
		SQL_LockDatabase(DBIDB); //non threading operations here, done once on plugin load only, not map change
		
		//war3sourceraces
		PrintToServer("[War3Source] Dropping war3sourceraces and recreating it (normal)") ;
		if(!SQL_FastQueryLogOnError(DBIDB,"DROP TABLE war3sourceraces")){
			PrintToServer("[War3Source] Table: war3sourceraces didnt exist or failed to drop it");
		}
		
		new String:longquery[4000];
		Format(longquery,sizeof(longquery),"CREATE TABLE war3sourceraces (");
		Format(longquery,sizeof(longquery),"%s %s",longquery,"shortname varchar(16) UNIQUE,");
		Format(longquery,sizeof(longquery),"%s %s",longquery,"name  varchar(32)");
		
		for(new i=0;i<MAXSKILLCOUNT;i++){
			Format(longquery,sizeof(longquery),"%s, skill%d varchar(32)",longquery,i);
			Format(longquery,sizeof(longquery),"%s, skilldesc%d varchar(2000)",longquery,i);
		}
		
		Format(longquery,sizeof(longquery),"%s )",longquery);
		
		SQL_FastQueryLogOnError(DBIDB,longquery);
		
		
		
		
		//war3source main table
		new bool:dropandcreatetable=false;
		// Database conversion methods
		new Handle:query=SQL_Query(DBIDB,"SELECT * from war3source LIMIT 1");
		
		
		if(query==INVALID_HANDLE)
		{   //query failed no result, re create table (table doesnt exist)
			dropandcreatetable=true;
		}
		else
		{	//ok table exists
			//SQL_Rewind(query);
			//if(SQL_FetchRow(query))
			//{
			//new count=SQL_GetFieldCount(query);
			
			///if column not there then add
			new dummyfield;
			if(!SQL_FieldNameToNum(query, "levelbankV2", dummyfield))
			{
				AddColumn(DBIDB,"levelbankV2","int","war3source");
				PrintToServer("[War3Source] Tried to ADD column in TABLE %s: %s","war3source","levelbankV2");
			}
			
			if(!SQL_FieldNameToNum(query, "gold", dummyfield))
			{
				if(g_SQLType==SQLType_SQLite){
					//sqlite cannot rename column
					AddColumn(DBIDB,"gold","INT","war3source");
				}
				else{
					SQL_FastQueryLogOnError(DBIDB,"ALTER TABLE war3source CHANGE credits gold INT");
				}
				PrintToServer("[War3Source] Tried to change column from 'credits' to 'gold'");
			}
			
			//}
			//else{   ///zero rows, just drop and recreate
			//	dropandcreatetable=true;
			//}
			CloseHandle(query);
		}
		
		
		
		if(dropandcreatetable)
		{
			PrintToServer("[War3Source] Dropping war3source main table and recreating it!!!") ;
			SQL_FastQueryLogOnError(DBIDB,"DROP TABLE war3source");
			if(!SQL_FastQueryLogOnError(DBIDB,"CREATE TABLE war3source (steamid varchar(64) UNIQUE , name varchar(64),   currentrace varchar(16),     gold int,      total_level int,     total_xp int, levelbankV2 int,   last_seen int)"  ))
			{
				SetFailState("[War3Source] ERROR in the creation of the SQL table war3source.");
			}
		}
		
		
		
		
		///NEW DATABASE STRUCTURE
		new bool:createtablexpdata=false;
		query=SQL_Query(DBIDB,"SELECT * from war3source_racedata1 LIMIT 1");
		if(query==INVALID_HANDLE)
		{   
			//query failed no result, re create table (table doesnt exist)
			//best not to drop our xp rables
			PrintToServer("[War3Source] war3source_racedata1 doesnt exist or has no entries, recreating!!!") ;
			createtablexpdata=true;
			
		}
		//implement later to check for skill# columns
		else
		{	//ok table exists
			
			new String:columnname[16];
			new dummyfield;
			
			for(new i=0;i<MAXSKILLCOUNT;i++){
				Format(columnname,sizeof(columnname),"skill%d",i);
				
				if(!SQL_FieldNameToNum(query, columnname , dummyfield))
				{
					AddColumn(DBIDB,columnname,"int","war3source_racedata1");
					PrintToServer("Tried to ADD column in TABLE %s: %s ","war3source_racedata1",columnname);
				}
				
			}
			CloseHandle(query);
		}
		if(createtablexpdata){
			
			//sqlite and mysql compatable
			
			//last_seen int
			new String:longquery2[4000];
			Format(longquery2,sizeof(longquery2),"CREATE TABLE war3source_racedata1 (steamid varchar(64)  , raceshortname varchar(16),   level int,  xp int");
			
			
			for(new skillid=0;skillid<MAXSKILLCOUNT ;skillid++){
				Format(longquery2,sizeof(longquery2),"%s, skill%d int ",longquery2,skillid);
			}
			Format(longquery2,sizeof(longquery2),"%s, last_seen int)",longquery2);
			
			
			if(!SQL_FastQueryLogOnError(DBIDB,longquery2)
			||
			!SQL_FastQueryLogOnError(DBIDB,"CREATE UNIQUE INDEX steamid ON war3source_racedata1 (steamid,raceshortname)")
			)
			{
				SetFailState("[War3Source] ERROR in the creation of the SQL table war3source_racedata1");
			}
		}
		
		
		
		
		
		
		
		SQL_UnlockDatabase(DBIDB);
	}
	else
		PrintToServer("DBIDB invalid 123");
}

//SAVING SECTION



War3Source_SavePlayerData(client,race)
{
	if(DBIDB && !IsFakeClient(client)&&W3IsPlayerXPLoaded(client))
	{
		War3_SavePlayerRace(client,race); //only save their current race
		War3_SavePlayerMainData(client);//main data
	}
}
	






/// General callback for threaded queries.  No Actions
public SQLWar3GeneralCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	//unansweredqueries--;
	//if(idebug>0){
	//	PrintToServer("[mysqlgolddebug] Got answer, query UNANSWERED %d",unansweredqueries);
	//}
	
	
	SQLCheckForErrors(hndl,error,"SQLWar3GeneralCallback");
}

stock SQLCheckForErrors(Handle:hndl,const String:originalerror[],const String:prependstr[]=""){
	if(!StrEqual("", originalerror))
		LogError("SQL error: [%s] %s", prependstr, originalerror);
	else if(hndl == INVALID_HANDLE)
	{
		decl String:err[512];
		SQL_GetError(hndl, err, sizeof(err));
		LogError("SQLCheckForErrors: [%s] %s", prependstr, err);
	}
}

public bool:SQL_FastQueryLogOnError(Handle:DB,const String:query[]){
	if(!SQL_FastQuery(DB,query)){
		new String:error[256];
		SQL_GetError(DB, error, sizeof(error));
		LogError("SQLFastQuery %s failed, Error: %s",query,error);
		return false;
	}
	return true;
}

public bool:SQL_War3_NormalQuery(Handle:DB,String:querystr[]){
	new Handle:result= SQL_Query(DB, querystr);
	if(result==INVALID_HANDLE) {
		new String:error[256];
		SQL_GetError(DB, error, sizeof(error));
		LogError("SQL_War3_NormalQuery %s failed, Error: %s",querystr,error);
		return false;
	}
	return true;
}
	



//retrieve//retrieve

//retrieve

//retrieve
//retrieve
public OnClientPutInServer(client)
{
	if(W3()){
		W3SetPlayerProp(client,xpLoaded,false);
	
		W3CreateEvent(ClearPlayerVariables,client); 
		W3CreateEvent(InitPlayerVariables,client); 
		
		
		if(W3SaveEnabled())
		{
			War3_ChatMessage(client,"%T","Loading player data...",client);
			War3Source_LoadPlayerData(client);
		}
		else{
			DoForwardOnWar3PlayerAuthed(client);
		}
		if(!W3SaveEnabled() || DBIDB==INVALID_HANDLE)
			W3SetPlayerProp(client,xpLoaded,true); // if db failed , or no save xp
	}
}
public OnClientDisconnect(client)
{
	if(W3()){
		if(W3SaveEnabled() && W3IsPlayerXPLoaded(client))
			War3Source_SavePlayerData(client,War3_GetRace(client));
		
		W3CreateEvent(ClearPlayerVariables,client); 
		
		desiredRaceOnJoin[client]=0;
	}
}

//SELECT STATEMENTS HERE
War3Source_LoadPlayerData(client) //war3source calls this
{
	//need space for steam id
	decl String:steamid[64];
	
	if(DBIDB && /*!IsFakeClient(client) && */GetClientAuthString(client,steamid,sizeof(steamid))) // no bots and steamid
	{
		
		new String:longquery[4000];
		//Prepare select query for main data
		Format(longquery,sizeof(longquery),"SELECT currentrace,gold,levelbankV2 FROM war3source WHERE steamid='%s'",steamid);
		//Pass off to threaded call back at normal prority
		SQL_TQuery(DBIDB,T_CallbackSelectPDataMain,longquery,client);
		
		PrintToConsole(client,"%T","[War3Source] XP retrieval query: sending MAIN and load all races request! Time: {amount}",client,GetGameTime());
		W3SetPlayerProp(client,sqlStartLoadXPTime,GetGameTime());
		
		//Lets get race data too
		
		Format(longquery,sizeof(longquery),"SELECT * FROM war3source_racedata1 WHERE steamid='%s'",steamid);
		SQL_TQuery(DBIDB,T_CallbackSelectPDataRace,longquery,client);
		
	}
}

public T_CallbackSelectPDataMain(Handle:owner,Handle:hndl,const String:error[],any:client)
{
	SQLCheckForErrors(hndl,error,"T_CallbackSelectPDataMain");
	
	if(!ValidPlayer(client))
		return;
	
	if(hndl==INVALID_HANDLE)
	{
		//Well the database is fucked up
		//TODO: add retry for select query
		LogError("[War3Source] ERROR: SELECT player data failed! Check DATABASE settings!");
		//Don't hang up the process for now
	}
	
	else
	{
		if(SQL_GetRowCount(hndl) == 1) 
		{
			SQL_Rewind(hndl);
			
			if(!SQL_FetchRow(hndl))
			{
				//This would be pretty fucked to occur here
				LogError("[War3Source] Unexpected error loading player data, could not FETCH row. Check DATABASE settings!");
				return;
			}
			else{
				//Get the gold from the query
				new cred=W3SQLPlayerInt(hndl,"gold");
				//Set the gold for player
				War3_SetGold(client,cred);
				
				new levelbankamount=W3SQLPlayerInt(hndl,"levelbankV2");
				
				if(W3GetLevelBank(client)>levelbankamount){ //whichever is higher
					levelbankamount=W3GetLevelBank(client); 
				}
				W3SetLevelBank(client,levelbankamount);
				
				
				
				//Get the short race string
				new String:currentrace[16];
				if(!W3SQLPlayerString(hndl,"currentrace",currentrace,sizeof(currentrace)))
				{
					LogError("[War3Source] Unexpected error loading player currentrace. Check DATABASE settings!");
					return;
				}
				PrintToConsole(client,"%T","[War3Source] War3 MAIN retrieval: gold {amount} Time {amount}",client,cred,GetGameTime());
				
				new raceFound=0; // worst case senario set player to race 0
				if(GetConVarInt(hSetRaceOnJoinCvar)>0)
				{
					//Scan all the races
					new RacesLoaded = War3_GetRacesLoaded();
					for(new x=1;x<=RacesLoaded;x++)
					{
						new String:short[16];
						War3_GetRaceShortname(x,short,sizeof(short));
						
						//compare their short names to the one loaded
						if(StrEqual(currentrace,short,false))
						{
							raceFound=x;
							break;
						}
					}
					desiredRaceOnJoin[client]=raceFound;
					
				}
			}
		}
		else if(SQL_GetRowCount(hndl) == 0) //he doesnt exist
		{
			//Not in database so add
			decl String:steamid[64];
			decl String:name[64];
			//get their name and steamid
			if(GetClientAuthString(client,steamid,sizeof(steamid)) && GetClientName(client,name,sizeof(name))) // steamid
			{
				ReplaceString(name,sizeof(name), "'","", true);//REMOVE IT//double escape because \\ turns into -> \  after the %s insert into sql statement
				
				new total_level=W3GetTotalLevels(client);
				new total_xp=0;
				
				// Get data from the player vector I guess this allows the player to play before the queries are
				// done but it is probably zero all the time
				new RacesLoaded = War3_GetRacesLoaded();
				for(new z=1;z<=RacesLoaded;z++)
				{
					total_xp+=War3_GetXP(client,z);
				}
				
				new String:short_name[16];
				War3_GetRaceShortname(War3_GetRace(client),short_name,sizeof(short_name));
				
				new String:longquery[4000];
				// Main table query
				Format(longquery,sizeof(longquery),"INSERT INTO war3source (steamid,name,currentrace,total_level,total_xp) VALUES ('%s','%s','%s','%d','%d')",steamid,name,short_name,total_level,total_xp);
				SQL_TQuery(DBIDB,T_CallbackInsertPDataMain,longquery,client);
			}
			
		}
		else if(SQL_GetRowCount(hndl) >1)
		{
			// this is a WTF moment here
			//should probably purge these records and get the player to rejoin but I'm lazy
			//and don't want to write that
			LogError("[War3Source] Returned more than 1 record, primary or UNIQUE keys are screwed (main, rows: %d)",SQL_GetRowCount(hndl));
		}
	}
}


//we just tried inserting main data
public T_CallbackInsertPDataMain(Handle:owner,Handle:query,const String:error[],any:client)
{
	SQLCheckForErrors(query,error,"T_CallbackInsertPDataMain");
}







///callback retrieved individual race xp!!!!!
public T_CallbackSelectPDataRace(Handle:owner,Handle:hndl,const String:error[],any:client)
{
	SQLCheckForErrors(hndl,error,"T_CallbackSelectPDataRace");
	
	if(!ValidPlayer(client))
		return;
	
	
	
	if(hndl!=INVALID_HANDLE)
	{
		new retrievals;
		new usefulretrievals;
		new bool:raceloaded[MAXRACES];
		while(SQL_MoreRows(hndl))
		{
			if(SQL_FetchRow(hndl)){ //SQLITE doesnt properly detect ending
				// Load up the data from a successful query
				// level,xp,skill1,skill2,skill3,ultimate
				
				new String:raceshortname[16];
				W3SQLPlayerString(hndl,"raceshortname",raceshortname,sizeof(raceshortname));
				new raceid=War3_GetRaceIDByShortname(raceshortname);
				if(raceid>0) //this race was loaded in war3
				{
					
					raceloaded[raceid]=true;
					new level=W3SQLPlayerInt(hndl,"level");
					
					if(level>W3GetRaceMaxLevel(raceid)){
						level=W3GetRaceMaxLevel(raceid);
					}
					
					War3_SetLevel(client,raceid,level);
					new pxp=W3SQLPlayerInt(hndl,"xp");
					War3_SetXP(client,raceid,pxp);
					
					
					new String:printstr[500];
					Format(printstr,sizeof(printstr),"%T","[War3Source] XP Ret: Race {race} Level {amount} XP {amount} Time {amount}...",client,raceshortname,level,pxp,GetGameTime());
					
					
					
					new String:column[32];
					new skilllevel;
					new RacesSkillCount = War3_GetRaceSkillCount(raceid);
					for(new skillid=0;skillid<RacesSkillCount;skillid++){
						Format(column,sizeof(column),"skill%d",skillid);
						skilllevel=W3SQLPlayerInt(hndl,column);
						War3_SetSkillLevel(client,raceid,skillid,skilllevel);
						
						Format(printstr,sizeof(printstr),"%s skill%d=%d",printstr,skillid,skilllevel);
					}
					
					usefulretrievals++;
				}
				retrievals++;
			}
		} 
		if(retrievals>0){
			PrintToConsole(client,"%T","[War3Source] Successfully retrieved data races, total of {amount} races were returned, {amount} are running on this server",client,retrievals,usefulretrievals);
		}
		else if(retrievals==0&&War3_GetRacesLoaded()>0){     //no xp record
			
			W3CreateEvent(PlayerIsNewToServer,client);
		}
		new inserts;
		new RacesLoaded = War3_GetRacesLoaded()
		for(new raceid=1;raceid<=RacesLoaded;raceid++)
		{
			
			if(raceloaded[raceid]==false){
				
				
				//no record make one
				decl String:steamid[64];
				decl String:name[64];
				if(GetClientAuthString(client,steamid,sizeof(steamid)) && GetClientName(client,name,sizeof(name)) ) {
					ReplaceString(name,sizeof(name), "'","", true);//REMOVE IT //double escape because \\ turns into -> \  after the %s insert into sql statement
					
					
					new String:longquery[4000];
					new String:short[16];
					War3_GetRaceShortname(raceid,short,sizeof(short));
					
					new last_seen=GetTime();
					Format(longquery,sizeof(longquery),"INSERT INTO war3source_racedata1 (steamid,raceshortname,level,xp,last_seen) VALUES ('%s','%s','%d','%d','%d')",steamid,short,War3_GetLevel(client,raceid),War3_GetXP(client,raceid),last_seen);
					
					SQL_TQuery(DBIDB,T_CallbackInsertPDataRace,longquery,client);
					inserts++;
				}
			}
			
		}
		if(inserts>0){
			
			PrintToConsole(client,"%T","[War3Source] Inserting fresh level xp data for {amount} races",client,inserts);
		}

		
		W3SetPlayerProp(client,xpLoaded,true);
		War3_ChatMessage(client,"%T","Successfully retrieved save data",client);
		PrintToConsole(client,"%T","[War3Source] XP RETRIEVED IN {amount} seconds",client,GetGameTime()-Float:W3GetPlayerProp(client,sqlStartLoadXPTime)) ;
		DoForwardOnWar3PlayerAuthed(client);
		
		if(War3_GetRace(client)<=0){
		//PrintToServer("shoudl set race? %d client %d",raceDesiredOnJoin,client);
			new bool:doset=true;
			if(GetConVarInt(W3GetVar(hRaceLimitEnabledCvar))>0){
				if(GetRacesOnTeam(desiredRaceOnJoin[client],GetClientTeam(client))>=W3GetRaceMaxLimitTeam(desiredRaceOnJoin[client],GetClientTeam(client)))
				{
					doset=false;
					War3_ChatMessage(client,"%T","Race limit for your team has been reached, please select a different race. (MAX {amount})",client,W3GetRaceMaxLimitTeam(desiredRaceOnJoin[client],GetClientTeam(client)));
					W3Log("race %d blocked on client %d due to restrictions limit %d (set race on join)",desiredRaceOnJoin[client],client,W3GetRaceMaxLimitTeam(desiredRaceOnJoin[client],GetClientTeam(client)));
					W3CreateEvent(DoShowChangeRaceMenu,client);
					
				}
				
			}
			if(doset){ ///player race was set on join, 
				W3SetPlayerProp(client,RaceSetByAdmin,false);
				War3_SetRace(client,desiredRaceOnJoin[client]);
			}
			else{  ///player race NOT was set on join, show menu
				W3CreateEvent(DoShowChangeRaceMenu,client);
			}
		}
	}
}


public T_CallbackInsertPDataRace(Handle:owner,Handle:query,const String:error[],any:data)
{
	SQLCheckForErrors(query,error,"T_CallbackInsertPDataRace");
}






///SAVE
///SAVE
///SAVE
///SAVE
///SAVE
///SAVE
///SAVE
///SAVE
///SAVE









//saveing section
//save a race using new db style
War3_SavePlayerRace(client,race)
{
	if(DBIDB && W3SaveEnabled() && W3GetPlayerProp(client,xpLoaded)&&race>0)
	{
		//PrintToServer("race %d client %d",race,client);
		decl String:steamid[64];
	
		if(GetClientAuthString(client,steamid,sizeof(steamid)))
		{
		
			
			new level=War3_GetLevel(client,race);
			new xp=War3_GetXP(client,race);
			
			new String:raceshortname[16];
			War3_GetRaceShortname(race,raceshortname,sizeof(raceshortname));
			
			
			new String:longquery[4000];
			Format(longquery,sizeof(longquery),"UPDATE war3source_racedata1 SET level='%d',xp='%d' ",level,xp);
			
			new SkillCount = War3_GetRaceSkillCount(race);
			for(new skillid=0;skillid<SkillCount;skillid++){
				Format(longquery,sizeof(longquery),"%s, skill%d=%d ",longquery,skillid,War3_GetSkillLevel(client,race,skillid));
			}
			
			new last_seen=GetTime();
			Format(longquery,sizeof(longquery),"%s , last_seen='%d' WHERE steamid='%s' AND raceshortname='%s'",longquery,last_seen,steamid,raceshortname);
			
			new String:racename[64];
			War3_GetRaceName(race,racename,sizeof(racename));
			PrintToConsole(client,"%T","[War3Source] Saving XP for race {racename}: LVL {amount} XP {amount}",client,racename,level,xp);
			
			//XP safety?
			//	new level=War3_GetLevel(client,x);
			//	if(level<W3GetRaceMaxLevel(x)){
			//		Format(longquery,sizeof(longquery),"%s AND level<='%d'",query_buffer,templevel); //only level restrict if not max, iif max or over do not restrict
			//	}
			
			
			SQL_TQuery(DBIDB,T_CallbackSavePlayerRace,longquery,client);
			
		}
	}
}
public T_CallbackSavePlayerRace(Handle:owner,Handle:hndl,const String:error[],any:client)
{
	SQLCheckForErrors(hndl,error,"T_CallbackSavePlayerRace");
}



War3_SavePlayerMainData(client){
	if(DBIDB &&W3IsPlayerXPLoaded(client))
	{
		//PrintToServer("client %d mainxp",client);
		decl String:steamid[64];
		decl String:name[64];
		if(GetClientAuthString(client,steamid,sizeof(steamid)) && GetClientName(client,name,sizeof(name)))
		{
			ReplaceString(name,sizeof(name), "'","", true);//REMOVE IT //double escape because \\ turns into -> \  after the %s insert into sql statement
			
				
			new String:longquery[4000];
			new total_level=W3GetTotalLevels(client);
			new total_xp=0;
			new RacesLoaded = War3_GetRacesLoaded();
			for(new z=1;z<=RacesLoaded;z++)
			{
				total_xp+=War3_GetXP(client,z);
			}
				
			new last_seen=GetTime();
			
			new String:short[16];
			War3_GetRaceShortname(War3_GetRace(client),short,sizeof(short));
			Format(longquery,sizeof(longquery),"UPDATE war3source SET name='%s',currentrace='%s',gold='%d',total_level='%d',total_xp='%d',last_seen='%d',levelbankV2='%d' WHERE steamid = '%s'",name,short,War3_GetGold(client),total_level,total_xp,last_seen,W3GetLevelBank(client),steamid);
			SQL_TQuery(DBIDB,T_CallbackUpdatePDataMain,longquery,client);
		}
	}
}

//we just tried inserting main data
public T_CallbackUpdatePDataMain(Handle:owner,Handle:query,const String:error[],any:client)
{
	SQLCheckForErrors(query,error,"T_CallbackUpdatePDataMain");
}

DoForwardOnWar3PlayerAuthed(client){
	Call_StartForward(g_OnWar3PlayerAuthedHandle);
	Call_PushCell(client);
	Call_Finish(dummy);
}

