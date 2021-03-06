/**
* File: events.inc
* Description: The handler for all the source engine event based stuff.
* Author(s): Anthony Iacono  
*/


new iRoundNumber;

public bool:War3Source_HookEvents()
{
	// Events for all games
	if(!HookEventEx("player_spawn",War3Source_PlayerSpawnEvent,EventHookMode_Pre)) //,EventHookMode_Pre
	{
		PrintToServer("[War3Source] Could not hook the player_spawn event.");
		return false;
	}
	if(!HookEventEx("player_death",War3Source_PlayerDeathEvent,EventHookMode_Pre))
	{
		PrintToServer("[War3Source] Could not hook the player_death event.");
		return false;
	}
	if(War3_GetGame()==Game_CS)
	{
		if(!HookEventEx("round_start",War3Source_RoundStartEvent))
		{
			PrintToServer("[War3Source] Could not hook the round_start event.");
			return false;
		}
		iRoundNumber=0;
		bInFreezeTime=false;
		
		if(!HookEventEx("round_end",War3Source_RoundOverEvent))
		{
			PrintToServer("[War3Source] Could not hook the round_end event.");
			return false;
		}
	}
	else if(War3_GetGame()==Game_DOD)
	{
		// TODO: DOD specific events
	}
	else if(War3_GetGame()==Game_TF)
	{
		if(!HookEventEx("teamplay_round_win",War3Source_RoundOverEvent))
		{
			PrintToServer("[War3Source] Could not hook the teamplay_round_win event.");
			return false;
		}

	}
	
	return true;
	
}

public War3Source_PlayerSpawnEvent(Handle:event,const String:name[],bool:dontBroadcast)
{
	if(GetEventInt(event,"userid")>0)
	{
		new client=GetClientOfUserId(GetEventInt(event,"userid"));
		if(ValidPlayer(client,true))
		{
			
			///DP("spawn %d",client);
			
			
			
			//bIgnoreTrackGF[client]=false;
			War3_SetMaxHP_INTERNAL(client,GetClientHealth(client));
			//PrintToChatAll("%d",GetClientHealth(index)); 
			
			if(W3()){
				CheckPendingRace(client);
				
				if(IsFakeClient(client)&&W3IsPlayerXPLoaded(client)&&War3_GetRace(client)==0&&GetConVarInt(botsetraces)){ //W3IsPlayerXPLoaded(client) is for skipping until putin server is fired (which cleared variables)
					new tries=100;
					if(tries>0){
						new race=GetRandomInt(1,War3_GetRacesLoaded());
						if(!W3RaceHasFlag(race,"nobots")){
							tries=0;
							//PrintToServer("race to be %d",race);
							War3_SetRace(client,race);
							War3_SetLevel(client,race,W3GetRaceMaxLevel(race));
							for(new i=1;i<=War3_GetRaceSkillCount(race);i++){
								War3_SetSkillLevelINTERNAL(client,race,i,W3GetRaceSkillMaxLevel(race,i));
							}
							W3DoLevelCheck(client);
						}
					}
					//PrintToServer("race %d level %d %d",War3_GetRace(client),War3_GetLevel(client,race),War3_GetSkillLevel(client,race,0));
				
				}
				
				
				
				new raceid=War3_GetRace(client);
				if(!W3GetPlayerProp(client,SpawnedOnce))
				{
					War3Source_IntroMenu(client);
					W3SetPlayerProp(client,SpawnedOnce,true);
				}
				else if(raceid<1&&W3IsPlayerXPLoaded(client))
				{
					ShowChangeRaceMenu(client);
				}
				else if(raceid>0&&GetConVarInt(hRaceLimitEnabled)>0&&GetRacesOnTeam(raceid,GetClientTeam(client),true)>W3GetRaceMaxLimitTeam(raceid,GetClientTeam(client))){
					CheckRaceTeamLimit(raceid,GetClientTeam(client));  //show changerace inside
				}
				raceid=War3_GetRace(client);//get again it may have changed
				if(raceid>0){
					
					W3DoLevelCheck(client);
					War3_ShowXP(client);
					
					W3CreateEvent(DoCheckRestrictedItems,client);
				}
				
				
			}
			
			//forward to all other plugins last
			DoForward_OnWar3EventSpawn(client);
			
			W3SetPlayerProp(client,bStatefulSpawn,false); //no longer a "stateful" spawn
		}
	}
}


public  Action:War3Source_PlayerDeathEvent(Handle:event,const String:name[],bool:dontBroadcast)
{
	new uid_victim = GetEventInt(event, "userid");
	new uid_attacker = GetEventInt(event, "attacker");
	new uid_entity = GetEventInt(event, "entityid");
	
	new victimIndex = 0;
	new attackerIndex = 0;
	
	if(uid_attacker>0){
		attackerIndex=GetClientOfUserId(uid_attacker);
	}
	
	if (War3_IsL4DEngine() && War3_IsCommonInfected(uid_entity))
	{
		W3VarArr[DeathRace]=War3_GetRace(victimIndex);
		new Handle:oldevent=W3GetVar(SmEvent);
		W3SetVar(SmEvent,event); //stacking on stack 
		
		W3SetVar(EventArg1, attackerIndex);
		//W3CreateEvent(OnDeathPre, uid_entity);
		
		//post death event actual forward
		DoForward_OnWar3EventDeath(uid_entity, attackerIndex,W3VarArr[DeathRace]);
		
		W3SetVar(SmEvent,oldevent); //restore on stack , if any
		return Plugin_Continue;
	}
	else
	{
		victimIndex=GetClientOfUserId(uid_victim);
	}
	//new uid_assister=0;
	//if(War3_GetGame()==Game_TF)
	//{
	//	uid_assister=GetEventInt(event,"assister");
	//}
	
	new bool:deadringereath=false;
	if(uid_victim>0)
	{	
		new deathFlags = GetEventInt(event, "death_flags");
		if (War3_GetGame()==Game_TF&&deathFlags & 32) //TF_DEATHFLAG_DEADRINGER
		{
			deadringereath=true;
			//PrintToChat(client,"war3 debug: dead ringer kill");
		}
		else
		{
			W3DoLevelCheck(victimIndex);	
		}
	}
	
	if(bHasDiedThisFrame[victimIndex]>0){
		return Plugin_Handled;
	}
	bHasDiedThisFrame[victimIndex]++;
	//lastly
	//DP("died? %d",bHasDiedThisFrame[victimIndex]);
	if(victimIndex&&!deadringereath) //forward to all other plugins last
	{

		W3VarArr[DeathRace]=War3_GetRace(victimIndex);
		
		new Handle:oldevent=W3GetVar(SmEvent);
	//	DP("new event %d",event);
		W3SetVar(SmEvent,event); //stacking on stack 
		
		///pre death event, internal event
		W3SetVar(EventArg1,attackerIndex);
		W3CreateEvent(OnDeathPre,victimIndex);
		
		//post death event actual forward
		DoForward_OnWar3EventDeath(victimIndex,attackerIndex,W3VarArr[DeathRace]);
		
		W3SetVar(SmEvent,oldevent); //restore on stack , if any
		//DP("restore event %d",event);
		//then we allow change race AFTER death forward
		W3SetPlayerProp(victimIndex,bStatefulSpawn,true);//next spawn shall be stateful
		CheckPendingRace(victimIndex);
		
	}
	return Plugin_Continue;
}
public OnGameFrame(){
	for(new i=1;i<MAXPLAYERSCUSTOM;i++){
		bHasDiedThisFrame[i]=0;
	}
}
public Action:EndFreezeTime(Handle:timer,any:roundNum)
{
	if(roundNum==iRoundNumber)
	{
		bInFreezeTime=false;
	}
}

public War3Source_RoundStartEvent(Handle:event,const String:name[],bool:dontBroadcast)
{
	bInFreezeTime=true;
	++iRoundNumber;
	new Handle:freezeTimeCvar=FindConVar("mp_freezetime");
	if(freezeTimeCvar)
	{
		new Float:fFreezeTime=GetConVarFloat(freezeTimeCvar);
		if(fFreezeTime>0.0)
		{
			CreateTimer(fFreezeTime,EndFreezeTime,iRoundNumber);
		}
		else
		{
			bInFreezeTime=false;
		}
	}
	else
	{
		bInFreezeTime=false;
	}
}

public War3Source_RoundOverEvent(Handle:event,const String:name[],bool:dontBroadcast)
{
	// cs - int winner
	// tf2 - int team
	new team=-1;
	if(War3_GetGame()==Game_TF)
	{
		team=GetEventInt(event,"team");
	}
	else
	{
		team=GetEventInt(event,"winner");
	}
	if(team>-1)
	{
		//winner team...
	}
}

CheckPendingRace(client){
	new pendingrace=W3GetPendingRace(client);
	if(pendingrace>0)
	{
		W3SetPendingRace(client,-1);
		
		
		/*GetConVarInt(W3GetVar(hRaceLimitEnabledCvar))>0&&
		GetRacesOnTeam(pendingrace,GetClientTeam(client))>=W3GetRaceMaxLimitTeam(pendingrace,GetClientTeam(client))*/
		if(	CanSelectRace(client,pendingrace)||W3IsDeveloper(client)){
			War3_SetRace(client,pendingrace); 
		}
		else
		{   //already at limit
			//War3_ChatMessage(client,"%T","Race limit for your team has been reached, please select a different race. (MAX {amount})",GetTrans(),W3GetRaceMaxLimitTeam(pendingrace,GetClientTeam(client)));
			//W3Log("race %d blocked on client %d due to restrictions limit (CheckPendingRace)",pendingrace,client);
			W3CreateEvent(DoShowChangeRaceMenu,client);
		}
		
	}
	///wasnt pending
	else if(War3_GetRace(client)==0){
		W3CreateEvent(DoShowChangeRaceMenu,client);
	}
	else if(War3_GetRace(client)>0){
		if(!CanSelectRace(client,War3_GetRace(client))){
			War3_SetRace(client,0);
			PrintToConsole(client,"Your race is set to zero via gameevents.inc");
		}
	}
}


