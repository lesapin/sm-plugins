#if defined _tempstats_included_
    #endinput
#endif
#define _tempstats_included_

/**
 * Enable stat tracking for a client.
 *
 * @param client    Client index.
 */
native void TempStats_Start(int client);

/**
 * Finish stat tracking for a client and print a summary.
 *
 * @param client    Client index.
 */
native void TempStats_Stop(int client);

/**
 * Reset current stats for a client.
 *
 * @param client    Client index.
 */
native void TempStats_Reset(int client);

/**
 * Pretty print a row of players stats in their console.
 *
 * @param client    Client to print.
 * @param cols      Number of columns in the table.
 * @param ...       Any number of 
 *
 */
native void TempStats_PrettyPrint(int client, int cols, ...);
