#if defined _entcollector_included_
    #endinput
#endif
#define _entcollector_included_

/**
 *  Remove all entities collected for a client
 * 
 *  @param client    The client to clean up.
 *  @return          Number of entities removed.
 */
native int RemoveClientEntities(int client);


