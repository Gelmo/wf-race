/*
Copyright (C) 2009-2010 Chasseur de bots

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
*/
int numCheckpoints = 0;
bool demoRecording = false;
const int MAX_RECORDS = 3;

uint[] levelRecordSectors;
uint   levelRecordFinishTime;
String levelRecordPlayerName;

// ch : MM
const uint RECORD_SEND_INTERVAL = 5 * 60 * 1000;	// 5 minutes
uint lastRecordSent = 0;

class cRecordTime
{
    uint[] sectorTimes;
    uint   finishTime;
    String playerName;
    bool arraysSetUp;

    void setupArrays( int size )
    {
        this.sectorTimes.resize( size );

        for ( int i = 0; i < numCheckpoints; i++ )
            this.sectorTimes[i] = 0;

        this.arraysSetUp = true;
    }

    cRecordTime()
    {
        this.arraysSetUp = false;
        this.finishTime = 0;
    }

    ~cRecordTime() {}

    void Copy( cRecordTime &other )
    {
        if ( !this.arraysSetUp )
            return;

        this.finishTime = other.finishTime;
        this.playerName = other.playerName;
        for ( int i = 0; i < numCheckpoints; i++ )
            this.sectorTimes[i] = other.sectorTimes[i];
    }

    void Store( cClient @client )
    {
        if ( !this.arraysSetUp )
            return;

        cPlayerTime @playerTimer = @RACE_GetPlayerTimer( client );

        this.finishTime = playerTimer.finishTime;
        this.playerName = client.name;
        for ( int i = 0; i < numCheckpoints; i++ )
            this.sectorTimes[i] = playerTimer.sectorTimes[i];
    }
}

cRecordTime[] levelRecords( MAX_RECORDS );

class cPlayerTime
{
    uint[] sectorTimes;
    uint[] bestSectorTimes;
    uint startTime;
    uint finishTime;
    uint bestFinishTime;
    int currentSector;
    bool inRace;
    bool arraysSetUp;

    void setupArrays( int size )
    {
        this.sectorTimes.resize( size );
        this.bestSectorTimes.resize( size );
        this.arraysSetUp = true;
        this.clear();
    }

    void clear()
    {
        this.currentSector = 0;
        this.inRace = false;
        this.startTime = 0;
        this.finishTime = 0;
        this.bestFinishTime = 0;

        if ( !this.arraysSetUp )
            return;

        for ( int i = 0; i < numCheckpoints; i++ )
        {
            this.sectorTimes[i] = 0;
            this.bestSectorTimes[i] = 0;
        }
    }

    cPlayerTime()
    {
        this.arraysSetUp = false;
        this.clear();
    }

    ~cPlayerTime() {}

    void startRace( cClient @client )
    {
        this.currentSector = 0;
        this.inRace = true;
        this.startTime = levelTime;
        this.finishTime = 0;

        for ( int i = 0; i < numCheckpoints; i++ )
            this.sectorTimes[i] = 0;

        client.newRaceRun( numCheckpoints );
    }

    void cancelRace()
    {
        this.inRace = false;
    }

    void completeRace( cClient @client )
    {
        uint delta;
        String str;

        if ( this.startTime > levelTime ) // something is very wrong here
            return;

        client.addAward( S_COLOR_CYAN + "Race Finished!" );

        this.finishTime = levelTime - this.startTime;
        this.inRace = false;

        // send the final time to MM
        client.setRaceTime( -1, this.finishTime );

        // print the time differences with the best race of this player
        // green if player's best time at this sector, red if not improving previous best time
        if ( this.bestFinishTime == 0 )
        {
            delta = this.finishTime;
            str = S_COLOR_GREEN + " ";
        }
        else if ( this.finishTime <= this.bestFinishTime )
        {
            delta = this.bestFinishTime - this.finishTime;
            str = S_COLOR_GREEN + "-";
        }
        else
        {
            delta = this.finishTime - this.bestFinishTime;
            str = S_COLOR_RED + "+";
        }

        G_CenterPrintMsg( client.getEnt(), "Current: " + RACE_TimeToString( this.finishTime ) + "\n"
                          + str + RACE_TimeToString( delta ) );

        if ( this.bestFinishTime == 0 || this.finishTime < this.bestFinishTime )
        {
            client.addAward( S_COLOR_YELLOW + "Personal Record!" );
            // copy all the sectors into the new personal record backup
            this.bestFinishTime = this.finishTime;
            for ( int i = 0; i < numCheckpoints; i++ )
                this.bestSectorTimes[i] = this.sectorTimes[i];
        }

        // see if the player improved one of the top scores
        for ( int top = 0; top < MAX_RECORDS; top++ )
        {
            if ( levelRecords[top].finishTime == 0 || levelRecords[top].finishTime > this.finishTime )
            {
                // move the other records down
                for ( int i = MAX_RECORDS - 1; i > top; i-- )
                    levelRecords[i].Copy( levelRecords[i - 1] );

                levelRecords[top].Store( client );

                RACE_WriteTopScores();
                RACE_UpdateHUDTopScores();
                break;
            }
        }

        // set up for respawning the player with a delay
        cEntity @respawner = G_SpawnEntity( "race_respawner" );
        respawner.nextThink = levelTime + 5000;
        respawner.count = client.playerNum;

        G_AnnouncerSound( client, G_SoundIndex( "sounds/misc/timer_ploink" ), GS_MAX_TEAMS, false, null );
    }

    void touchCheckPoint( cClient @client, int id )
    {
        uint delta;
        String str;

        if ( id < 0 || id >= numCheckpoints )
            return;

        if ( !this.inRace )
            return;

        if ( this.sectorTimes[id] != 0 ) // already past this checkPoint
            return;

        if ( this.startTime > levelTime ) // something is very wrong here
            return;

        this.sectorTimes[id] = levelTime - this.startTime;

        // send this checkpoint to MM
        client.setRaceTime( id, this.sectorTimes[id] );

        // print some output and give awards if earned

        // green if player's best time at this sector, red if not improving previous best time
        if ( this.bestSectorTimes[id] == 0 )
        {
            delta = this.sectorTimes[id];
            str = S_COLOR_GREEN + " ";
        }
        else if ( this.sectorTimes[id] <= this.bestSectorTimes[id] )
        {
            delta = this.bestSectorTimes[id] - this.sectorTimes[id];
            str = S_COLOR_GREEN + "-";
            if ( this.sectorTimes[id] <= levelRecords[0].sectorTimes[id] )
                str += "R#1-"; // extra id when on server record beating time
            else if ( this.sectorTimes[id] <= levelRecords[1].sectorTimes[id] )
                str += "R#2-"; // extra id when on server record beating time
            else if ( this.sectorTimes[id] <= levelRecords[2].sectorTimes[id] )
                str += "R#3-"; // extra id when on server record beating time
        }
        else
        {
            delta = this.sectorTimes[id] - this.bestSectorTimes[id];
            str = S_COLOR_RED + "+";
        }

        G_CenterPrintMsg( client.getEnt(), "Current: " + RACE_TimeToString( this.sectorTimes[id] ) + "\n"
                          + str + RACE_TimeToString( delta ) );

        // if beating the level record on this sector give an award
        if ( this.sectorTimes[id] < levelRecords[0].sectorTimes[id] )
        {
            client.addAward( "Sector Record on sector " + this.currentSector + "!" );
        }
        // if beating his own record on this secotr give an award
        else if ( this.sectorTimes[id] < this.bestSectorTimes[id] )
        {
        	// ch : does racesow apply sector records only if race is completed?
            client.addAward( "Personal record on Sector " + this.currentSector + "!" );
            this.bestSectorTimes[id] = this.sectorTimes[id];
        }

        this.currentSector++;

        G_AnnouncerSound( client, G_SoundIndex( "sounds/misc/timer_bip_bip" ), GS_MAX_TEAMS, false, null );
    }
}

cPlayerTime[] cPlayerTimes( maxClients );

cPlayerTime @RACE_GetPlayerTimer( cClient @client )
{
    if ( @client == null || client.playerNum < 0 )
        return null;

    return @cPlayerTimes[ client.playerNum ];
}

// the player has finished the race. This entity times his automatic respawning
void race_respawner_think( cEntity @respawner )
{
    cClient @client = G_GetClient( respawner.count );

    // the client may have respawned on his own. If the last time was erased, don't respawn him
    if ( !RACE_GetPlayerTimer( client ).inRace && RACE_GetPlayerTimer( client ).finishTime != 0 )
        client.respawn( false );

    respawner.freeEntity(); // free the respawner
}

///*****************************************************************
/// NEW MAP ENTITY DEFINITIONS
///*****************************************************************

/**
 * Cgg - defrag support
 * target_init are meant to reset the player hp, armor and inventory.
 * spawnflags can be used to limit the effects of the target to certain types of items :
 *   - spawnflag 1 prevents the armor from being removed.
 *   - spawnflag 2 prevents the hp from being reset.
 *   - spawnflag 4 prevents the weapons and ammo from being removed.
 *   - spawnflag 8 prevents the powerups from being removed.
 *   - spawnflag 16 used to prevent the removal of the holdable items (namely the
 *     medkit and teleport) from the player inventory.
 */
void target_init_use( cEntity @self, cEntity @other, cEntity @activator )
{
    int i;

    if ( @activator.client == null )
        return;

    // armor
    if ( ( self.spawnFlags & 1 ) == 0 )
        activator.client.armor = 0;

    // health
    if ( ( self.spawnFlags & 2 ) == 0 )
    {
        activator.health = activator.maxHealth;
    }

    // weapons
    if ( ( self.spawnFlags & 4 ) == 0 )
    {
        for ( int i = WEAP_GUNBLADE; i < WEAP_TOTAL; i++ )
        {
            activator.client.inventorySetCount( i, 0 );
        }

        for ( int i = AMMO_WEAK_GUNBLADE; i < AMMO_TOTAL; i++ )
        {
            activator.client.inventorySetCount( i, 0 );
        }

        activator.client.inventorySetCount( WEAP_GUNBLADE, 1 );
        activator.client.selectWeapon( WEAP_GUNBLADE );
    }

    // powerups
    if ( ( self.spawnFlags & 8 ) == 0 )
    {
        for ( i = POWERUP_QUAD; i < POWERUP_TOTAL; i++ )
            activator.client.inventorySetCount( i, 0 );
    }
}

// doesn't need to do anything at all, just sit there, waiting
void target_init( cEntity @self )
{
	@self.use = target_init_use;
}

void target_checkpoint_use( cEntity @self, cEntity @other, cEntity @activator )
{
    if ( @activator.client == null )
        return;

    if ( !RACE_GetPlayerTimer( activator.client ).inRace )
        return;

    RACE_GetPlayerTimer( activator.client ).touchCheckPoint( activator.client, self.count );
}

void target_checkpoint( cEntity @self )
{
    self.count = numCheckpoints;
	@self.use = target_checkpoint_use;
    numCheckpoints++;
}

void target_stoptimer_use( cEntity @self, cEntity @other, cEntity @activator )
{
    if ( @activator.client == null )
        return;

    if ( !RACE_GetPlayerTimer( activator.client ).inRace )
        return;

    RACE_GetPlayerTimer( activator.client ).completeRace( activator.client );

    G_Print( activator.client.name + " crossed the finish line\n" );
}

// This sucks: some defrag maps have the entity classname with pseudo camel notation
// and classname->function is case sensitive

void target_stoptimer( cEntity @self )
{
	@self.use = target_stoptimer_use;
}

void target_stopTimer( cEntity @self )
{
	target_stoptimer( self );
}

void target_starttimer_use( cEntity @self, cEntity @other, cEntity @activator )
{
    if ( @activator.client == null )
        return;

    if ( RACE_GetPlayerTimer( activator.client ).inRace )
        return;

    RACE_GetPlayerTimer( activator.client ).startRace( activator.client );

    G_Print( activator.client.name + " started a new race\n" );

    int soundIndex = G_SoundIndex( "sounds/announcer/countdown/go0" + int( brandom( 1, 2 ) ) );
    G_AnnouncerSound( activator.client, soundIndex, GS_MAX_TEAMS, false, null );
}

// doesn't need to do anything at all, just sit there, waiting
void target_starttimer( cEntity @ent )
{
	@ent.use = target_starttimer_use;
}

void target_startTimer( cEntity @ent )
{
	target_starttimer( ent );
}

///*****************************************************************
/// LOCAL FUNCTIONS
///*****************************************************************

String RACE_TimeToString( uint time )
{
    // convert times to printable form
    String minsString, secsString, millString;
    uint min, sec, milli;

    milli = time;
    min = milli / 60000;
    milli -= min * 60000;
    sec = milli / 1000;
    milli -= sec * 1000;

    if ( min == 0 )
        minsString = "00";
    else if ( min < 10 )
        minsString = "0" + min;
    else
        minsString = min;

    if ( sec == 0 )
        secsString = "00";
    else if ( sec < 10 )
        secsString = "0" + sec;
    else
        secsString = sec;

    if ( milli == 0 )
        millString = "000";
    else if ( milli < 10 )
        millString = "00" + milli;
    else if ( milli < 100 )
        millString = "0" + milli;
    else
        millString = milli;

    return minsString + ":" + secsString + "." + millString;
}

void RACE_UpdateHUDTopScores()
{
    for ( int i = 0; i < MAX_RECORDS; i++ )
    {
        if ( levelRecords[i].finishTime > 0 && levelRecords[i].playerName.len() > 0 )
        {
            G_ConfigString( CS_GENERAL + i, "#" + ( i + 1 ) + " - " + levelRecords[i].playerName + " - " + RACE_TimeToString( levelRecords[i].finishTime ) );
        }
    }
}

void RACE_WriteTopScores()
{
    String topScores;
    Cvar mapName( "mapname", "", 0 );

    topScores = "//" + mapName.string + " top scores\n\n";

    for ( int i = 0; i < MAX_RECORDS; i++ )
    {
        if ( levelRecords[i].finishTime > 0 && levelRecords[i].playerName.len() > 0 )
        {
            topScores += "\"" + int( levelRecords[i].finishTime ) + "\" \"" + levelRecords[i].playerName + "\" ";

            // add the sectors
            topScores += "\"" + numCheckpoints+ "\" ";

            for ( int j = 0; j < numCheckpoints; j++ )
                topScores += "\"" + int( levelRecords[i].sectorTimes[j] ) + "\" ";

            topScores += "\n";
        }
    }

    G_WriteFile( "topscores/race/" + mapName.string + ".txt", topScores );
}

void RACE_LoadTopScores()
{
    String topScores;
    Cvar mapName( "mapname", "", 0 );

    topScores = G_LoadFile( "topscores/race/" + mapName.string + ".txt" );

    if ( topScores.len() > 0 )
    {
        String timeToken, nameToken, sectorToken;
        int count = 0;

        for ( int i = 0; i < MAX_RECORDS; i++ )
        {
            timeToken = topScores.getToken( count++ );
            if ( timeToken.len() == 0 )
                break;

            nameToken = topScores.getToken( count++ );
            if ( nameToken.len() == 0 )
                break;

            sectorToken = topScores.getToken( count++ );
            if ( sectorToken.len() == 0 )
                break;

            int numSectors = sectorToken.toInt();

            // store this one
            for ( int j = 0; j < numSectors; j++ )
            {
                sectorToken = topScores.getToken( count++ );
                if ( sectorToken.len() == 0 )
                    break;

                levelRecords[i].sectorTimes[j] = uint( sectorToken.toInt() );
            }

            levelRecords[i].finishTime = uint( timeToken.toInt() );
            levelRecords[i].playerName = nameToken;
        }

        RACE_UpdateHUDTopScores();
    }
}

// a player has just died. The script is warned about it so it can account scores
void RACE_playerKilled( cEntity @target, cEntity @attacker, cEntity @inflicter )
{
    if ( @target == null || @target.client == null )
        return;

    RACE_GetPlayerTimer( target.client ).cancelRace();
}

void RACE_SetUpMatch()
{
    int i, j;
    cEntity @ent;
    cTeam @team;

    gametype.shootingDisabled = false;
    gametype.readyAnnouncementEnabled = false;
    gametype.scoreAnnouncementEnabled = false;
    gametype.countdownEnabled = true;

    gametype.pickableItemsMask = gametype.spawnableItemsMask;
    gametype.dropableItemsMask = gametype.spawnableItemsMask;

    // clear player stats and scores, team scores

    for ( i = TEAM_PLAYERS; i < GS_MAX_TEAMS; i++ )
    {
        @team = @G_GetTeam( i );
        team.stats.clear();
    }

    G_RemoveDeadBodies();

    // ch : clear last recordSentTime
    lastRecordSent = levelTime;
}

///*****************************************************************
/// MODULE SCRIPT CALLS
///*****************************************************************

bool GT_Command( cClient @client, String &cmdString, String &argsString, int argc )
{
    if ( cmdString == "gametype" )
    {
        String response = "";
        Cvar fs_game( "fs_game", "", 0 );
        String manifest = gametype.manifest;

        response += "\n";
        response += "Gametype " + gametype.name + " : " + gametype.title + "\n";
        response += "----------------\n";
        response += "Version: " + gametype.version + "\n";
        response += "Author: " + gametype.author + "\n";
        response += "Mod: " + fs_game.string + (!manifest.empty() ? " (manifest: " + manifest + ")" : "") + "\n";
        response += "----------------\n";

        G_PrintMsg( client.getEnt(), response );
        return true;
    }
    else if ( cmdString == "cvarinfo" )
    {
        GENERIC_CheatVarResponse( client, cmdString, argsString, argc );
        return true;
    }
    else if ( ( cmdString == "racerestart" ) || ( cmdString == "restartrace" ) )
    {
        if ( @client != null )
        {
            if ( !RACE_GetPlayerTimer( client ).inRace )
            {
                G_PrintMsg( client.getEnt(), "You are not currently in a race\n" );
                return true;
            }

            RACE_GetPlayerTimer( client ).cancelRace();
            client.respawn( false );
        }

        return true;
    }

    return false;
}

// When this function is called the weights of items have been reset to their default values,
// this means, the weights *are set*, and what this function does is scaling them depending
// on the current bot status.
// Player, and non-item entities don't have any weight set. So they will be ignored by the bot
// unless a weight is assigned here.
bool GT_UpdateBotStatus( cEntity @self )
{
    return false; // let the default code handle it itself
}

// select a spawning point for a player
cEntity @GT_SelectSpawnPoint( cEntity @self )
{
    return GENERIC_SelectBestRandomSpawnPoint( self, "info_player_deathmatch" );
}

String @GT_ScoreboardMessage( uint maxlen )
{
    String scoreboardMessage = "";
    String entry;
    cTeam @team;
    cEntity @ent;
    int i, playerID;
    int racing;
    //int readyIcon;

    @team = @G_GetTeam( TEAM_PLAYERS );

    // &t = team tab, team tag, team score (doesn't apply), team ping (doesn't apply)
    entry = "&t " + int( TEAM_PLAYERS ) + " 0 " + team.ping + " ";
    if ( scoreboardMessage.len() + entry.len() < maxlen )
        scoreboardMessage += entry;

    // "Name Time Ping Racing"
    for ( i = 0; @team.ent( i ) != null; i++ )
    {
        @ent = @team.ent( i );

        int playerID = ( ent.isGhosting() && ( match.getState() == MATCH_STATE_PLAYTIME ) ) ? -( ent.playerNum + 1 ) : ent.playerNum;
        racing = int( RACE_GetPlayerTimer( ent.client ).inRace ? 1 : 0 );

        entry = "&p " + playerID + " " + ent.client.clanName + " "
                + RACE_GetPlayerTimer( ent.client ).bestFinishTime + " "
                + ent.client.ping + " " + racing + " ";

        if ( scoreboardMessage.len() + entry.len() < maxlen )
            scoreboardMessage += entry;
    }

    return scoreboardMessage;
}

// Some game actions trigger score events. These are events not related to killing
// oponents, like capturing a flag
// Warning: client can be null
void GT_scoreEvent( cClient @client, String &score_event, String &args )
{
    if ( score_event == "dmg" )
    {
    }
    else if ( score_event == "kill" )
    {
        cEntity @attacker = null;

        if ( @client != null )
            @attacker = @client.getEnt();

        int arg1 = args.getToken( 0 ).toInt();
        int arg2 = args.getToken( 1 ).toInt();

        // target, attacker, inflictor
        RACE_playerKilled( G_GetEntity( arg1 ), attacker, G_GetEntity( arg2 ) );
    }
    else if ( score_event == "award" )
    {
    }
    else if ( score_event == "enterGame" )
    {
    	if( @client != null )
			RACE_GetPlayerTimer( client ).clear();

    	// ch : begin fetching records over interweb
    	// MM_FetchRaceRecords( client.getEnt() );
    }
}

// a player is being respawned. This can happen from several ways, as dying, changing team,
// being moved to ghost state, be placed in respawn queue, being spawned from spawn queue, etc
void GT_playerRespawn( cEntity @ent, int old_team, int new_team )
{
    RACE_GetPlayerTimer( ent.client ).cancelRace();

    if ( ent.isGhosting() )
        return;

    // set player movement to pass through other players
    ent.client.setPMoveFeatures( ent.client.pmoveFeatures | PMFEAT_GHOSTMOVE );

    if ( gametype.isInstagib )
        ent.client.inventoryGiveItem( WEAP_INSTAGUN );
    else
        ent.client.inventorySetCount( WEAP_GUNBLADE, 1 );

    // select rocket launcher if available
    if ( ent.client.canSelectWeapon( WEAP_ROCKETLAUNCHER ) )
        ent.client.selectWeapon( WEAP_ROCKETLAUNCHER );
    else
        ent.client.selectWeapon( -1 ); // auto-select best weapon in the inventory

    // add a teleportation effect
    ent.respawnEffect();

    int soundIndex = G_SoundIndex( "sounds/announcer/countdown/ready0" + int( brandom( 1, 2 ) ) );
    G_AnnouncerSound( ent.client, soundIndex, GS_MAX_TEAMS, false, null );
}

// Thinking function. Called each frame
void GT_ThinkRules()
{
    if ( match.scoreLimitHit() || match.timeLimitHit() || match.suddenDeathFinished() )
        match.launchState( match.getState() + 1 );

    if ( match.getState() >= MATCH_STATE_POSTMATCH )
        return;

	GENERIC_Think();

    if ( match.getState() == MATCH_STATE_PLAYTIME )
    {
        // if there is no player in TEAM_PLAYERS finish the match and restart
        if ( G_GetTeam( TEAM_PLAYERS ).numPlayers == 0 && demoRecording )
        {
            match.stopAutorecord();
            demoRecording = false;
        }
        else if ( !demoRecording && G_GetTeam( TEAM_PLAYERS ).numPlayers > 0 )
        {
            match.startAutorecord();
            demoRecording = true;
        }
    }

    // set all clients race stats
    cClient @client;

    for ( int i = 0; i < maxClients; i++ )
    {
        @client = @G_GetClient( i );
        if ( client.state() < CS_SPAWNED )
            continue;

		// disable gunblade autoattack
		client.setPMoveFeatures( client.pmoveFeatures & ~PMFEAT_GUNBLADEAUTOATTACK );

        // always clear all before setting
        client.setHUDStat( STAT_PROGRESS_SELF, 0 );
        client.setHUDStat( STAT_PROGRESS_OTHER, 0 );
        client.setHUDStat( STAT_IMAGE_SELF, 0 );
        client.setHUDStat( STAT_IMAGE_OTHER, 0 );
        client.setHUDStat( STAT_PROGRESS_ALPHA, 0 );
        client.setHUDStat( STAT_PROGRESS_BETA, 0 );
        client.setHUDStat( STAT_IMAGE_ALPHA, 0 );
        client.setHUDStat( STAT_IMAGE_BETA, 0 );
        client.setHUDStat( STAT_MESSAGE_SELF, 0 );
        client.setHUDStat( STAT_MESSAGE_OTHER, 0 );
        client.setHUDStat( STAT_MESSAGE_ALPHA, 0 );
        client.setHUDStat( STAT_MESSAGE_BETA, 0 );

        // all stats are set to 0 each frame, so it's only needed to set a stat if it's going to get a value
        if ( RACE_GetPlayerTimer( client ).inRace )
            client.setHUDStat( STAT_TIME_SELF, (levelTime - RACE_GetPlayerTimer( client ).startTime) / 100 );

        client.setHUDStat( STAT_TIME_BEST, RACE_GetPlayerTimer( client ).bestFinishTime / 100 );
        client.setHUDStat( STAT_TIME_RECORD, levelRecords[0].finishTime / 100 );

        client.setHUDStat( STAT_TIME_ALPHA, -9999 );
        client.setHUDStat( STAT_TIME_BETA, -9999 );

        if ( levelRecords[0].playerName.len() > 0 )
            client.setHUDStat( STAT_MESSAGE_OTHER, CS_GENERAL );
        if ( levelRecords[1].playerName.len() > 0 )
            client.setHUDStat( STAT_MESSAGE_ALPHA, CS_GENERAL + 1 );
        if ( levelRecords[2].playerName.len() > 0 )
            client.setHUDStat( STAT_MESSAGE_BETA, CS_GENERAL + 2 );
    }

    // ch : send intermediate results
    if( ( lastRecordSent + RECORD_SEND_INTERVAL ) >= levelTime )
    {

    }
}

// The game has detected the end of the match state, but it
// doesn't advance it before calling this function.
// This function must give permission to move into the next
// state by returning true.
bool GT_MatchStateFinished( int incomingMatchState )
{
    if ( match.getState() == MATCH_STATE_POSTMATCH )
    {
        match.stopAutorecord();
        demoRecording = false;

        // ch : also send rest of results
        RACE_WriteTopScores();
    }

    return true;
}

// the match state has just moved into a new state. Here is the
// place to set up the new state rules
void GT_MatchStateStarted()
{
    switch ( match.getState() )
    {
    case MATCH_STATE_WARMUP:
        RACE_SetUpMatch();
        break;

    case MATCH_STATE_COUNTDOWN:
        break;

    case MATCH_STATE_PLAYTIME:
        RACE_SetUpMatch();
        break;

    case MATCH_STATE_POSTMATCH:
        gametype.pickableItemsMask = 0;
        gametype.dropableItemsMask = 0;
        GENERIC_SetUpEndMatch();
        break;

    default:
        break;
    }
}

// the gametype is shutting down cause of a match restart or map change
void GT_Shutdown()
{
}

// The map entities have just been spawned. The level is initialized for
// playing, but nothing has yet started.
void GT_SpawnGametype()
{
    //G_Print( "numCheckPoints: " + numCheckpoints + "\n" );

    // setup the checkpoints arrays sizes adjusted to numCheckPoints
    for ( int i = 0; i < maxClients; i++ )
        cPlayerTimes[i].setupArrays( numCheckpoints );

    for ( int i = 0; i < MAX_RECORDS; i++ )
        levelRecords[i].setupArrays( numCheckpoints );

    RACE_LoadTopScores();
}

// Important: This function is called before any entity is spawned, and
// spawning entities from it is forbidden. If you want to make any entity
// spawning at initialization do it in GT_SpawnGametype, which is called
// right after the map entities spawning.

void GT_InitGametype()
{
    gametype.title = "Race";
    gametype.version = "1.02";
    gametype.author = "Warsow Development Team";

    // if the gametype doesn't have a config file, create it
    if ( !G_FileExists( "configs/server/gametypes/" + gametype.name + ".cfg" ) )
    {
        String config;

        // the config file doesn't exist or it's empty, create it
        config = "// '" + gametype.title + "' gametype configuration file\n"
                 + "// This config will be executed each time the gametype is started\n"
                 + "\n\n// map rotation\n"
                 + "set g_maplist \"\" // list of maps in automatic rotation\n"
                 + "set g_maprotation \"0\"   // 0 = same map, 1 = in order, 2 = random\n"
                 + "\n// game settings\n"
                 + "set g_scorelimit \"0\"\n"
                 + "set g_timelimit \"0\"\n"
                 + "set g_warmup_timelimit \"0\"\n"
                 + "set g_match_extendedtime \"0\"\n"
                 + "set g_allow_falldamage \"0\"\n"
                 + "set g_allow_selfdamage \"0\"\n"
                 + "set g_allow_teamdamage \"0\"\n"
                 + "set g_allow_stun \"0\"\n"
                 + "set g_teams_maxplayers \"0\"\n"
                 + "set g_teams_allow_uneven \"0\"\n"
                 + "set g_countdown_time \"5\"\n"
                 + "set g_maxtimeouts \"-1\" // -1 = unlimited\n"
                 + "set g_challengers_queue \"0\"\n"
                 + "\necho " + gametype.name + ".cfg executed\n";

        G_WriteFile( "configs/server/gametypes/" + gametype.name + ".cfg", config );
        G_Print( "Created default config file for '" + gametype.name + "'\n" );
        G_CmdExecute( "exec configs/server/gametypes/" + gametype.name + ".cfg silent" );
    }

    gametype.spawnableItemsMask = ( IT_AMMO | IT_WEAPON | IT_POWERUP );
    if ( gametype.isInstagib )
        gametype.spawnableItemsMask &= ~uint(G_INSTAGIB_NEGATE_ITEMMASK);

    gametype.respawnableItemsMask = gametype.spawnableItemsMask;
    gametype.dropableItemsMask = 0;
    gametype.pickableItemsMask = ( gametype.spawnableItemsMask | gametype.dropableItemsMask );

    gametype.isTeamBased = false;
    gametype.isRace = true;
    gametype.hasChallengersQueue = false;
    gametype.maxPlayersPerTeam = 0;

    gametype.ammoRespawn = 1;
    gametype.armorRespawn = 1;
    gametype.weaponRespawn = 1;
    gametype.healthRespawn = 1;
    gametype.powerupRespawn = 1;
    gametype.megahealthRespawn = 1;
    gametype.ultrahealthRespawn = 1;

    gametype.readyAnnouncementEnabled = false;
    gametype.scoreAnnouncementEnabled = false;
    gametype.countdownEnabled = false;
    gametype.mathAbortDisabled = true;
    gametype.shootingDisabled = false;
    gametype.infiniteAmmo = true;
    gametype.canForceModels = true;
    gametype.canShowMinimap = false;
	gametype.teamOnlyMinimap = true;

    gametype.spawnpointRadius = 0;

    if ( gametype.isInstagib )
        gametype.spawnpointRadius *= 2;

    // set spawnsystem type
    for ( int team = TEAM_PLAYERS; team < GS_MAX_TEAMS; team++ )
        gametype.setTeamSpawnsystem( team, SPAWNSYSTEM_INSTANT, 0, 0, false );

    // define the scoreboard layout
    G_ConfigString( CS_SCB_PLAYERTAB_LAYOUT, "%n 112 %s 52 %t 96 %l 48 %b 48" );
    G_ConfigString( CS_SCB_PLAYERTAB_TITLES, "Name Clan Time Ping Racing" );

    // add commands
    G_RegisterCommand( "gametype" );
    G_RegisterCommand( "racerestart" );

    demoRecording = false;

    G_Print( "Gametype '" + gametype.title + "' initialized\n" );
}