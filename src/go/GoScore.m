// -----------------------------------------------------------------------------
// Copyright 2011-2013 Patrick Näf (herzbube@herzbube.ch)
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// -----------------------------------------------------------------------------


// Project includes
#import "GoScore.h"
#import "GoBoard.h"
#import "GoBoardPosition.h"
#import "GoBoardRegion.h"
#import "GoGame.h"
#import "GoMove.h"
#import "GoPlayer.h"
#import "GoPoint.h"
#import "../main/ApplicationDelegate.h"
#import "../gtp/GtpCommand.h"
#import "../gtp/GtpResponse.h"
#import "../utility/NSStringAdditions.h"
#import "../play/model/ScoringModel.h"


// -----------------------------------------------------------------------------
/// @brief Class extension with private properties for GoScore.
// -----------------------------------------------------------------------------
@interface GoScore()
@property(nonatomic, assign) GoGame* game;
@property(nonatomic, retain) NSOperationQueue* operationQueue;
@property(nonatomic, assign) bool didAskGtpEngineForDeadStones;
@property(nonatomic, assign) bool lastCalculationHadError;
@end


@implementation GoScore

// -----------------------------------------------------------------------------
/// @brief Initializes a GoScore object that operates on @a game.
///
/// @note This is the designated initializer of GoScore.
// -----------------------------------------------------------------------------
- (id) initWithGame:(GoGame*)game
{
  // Call designated initializer of superclass (NSObject)
  self = [super init];
  if (! self)
    return nil;

  _territoryScoringEnabled = false;              // don't use self to avoid triggering a notification
  _scoringInProgress = false;                    // ditto
  _askGtpEngineForDeadStonesInProgress = false;  // ditto
  _game = game;
  _operationQueue = [[NSOperationQueue alloc] init];
  _didAskGtpEngineForDeadStones = false;
  _lastCalculationHadError = false;
  [self resetValues];

  return self;
}

// -----------------------------------------------------------------------------
/// @brief NSCoding protocol method.
// -----------------------------------------------------------------------------
- (id) initWithCoder:(NSCoder*)decoder
{
  self = [super init];
  if (! self)
    return nil;

  if ([decoder decodeIntForKey:nscodingVersionKey] != nscodingVersion)
    return nil;
  _territoryScoringEnabled = [decoder decodeBoolForKey:goScoreTerritoryScoringEnabledKey];
  _scoringInProgress = [decoder decodeBoolForKey:goScoreScoringInProgressKey];
  _askGtpEngineForDeadStonesInProgress = [decoder decodeBoolForKey:goScoreAskGtpEngineForDeadStonesInProgressKey];
  _komi = [decoder decodeDoubleForKey:goScoreKomiKey];
  _capturedByBlack = [decoder decodeIntForKey:goScoreCapturedByBlackKey];
  _capturedByWhite = [decoder decodeIntForKey:goScoreCapturedByWhiteKey];
  _deadBlack = [decoder decodeIntForKey:goScoreDeadBlackKey];
  _deadWhite = [decoder decodeIntForKey:goScoreDeadWhiteKey];
  _territoryBlack = [decoder decodeIntForKey:goScoreTerritoryBlackKey];
  _territoryWhite = [decoder decodeIntForKey:goScoreTerritoryWhiteKey];
  _totalScoreBlack = [decoder decodeIntForKey:goScoreTotalScoreBlackKey];
  _totalScoreWhite = [decoder decodeDoubleForKey:goScoreTotalScoreWhiteKey];
  _result = [decoder decodeIntForKey:goScoreResultKey];
  _numberOfMoves = [decoder decodeIntForKey:goScoreNumberOfMovesKey];
  _stonesPlayedByBlack = [decoder decodeIntForKey:goScoreStonesPlayedByBlackKey];
  _stonesPlayedByWhite = [decoder decodeIntForKey:goScoreStonesPlayedByWhiteKey];
  _passesPlayedByBlack = [decoder decodeIntForKey:goScorePassesPlayedByBlackKey];
  _passesPlayedByWhite = [decoder decodeIntForKey:goScorePassesPlayedByWhiteKey];
  _game = [decoder decodeObjectForKey:goScoreGameKey];
  _didAskGtpEngineForDeadStones = [decoder decodeBoolForKey:goScoreDidAskGtpEngineForDeadStonesKey];
  _lastCalculationHadError = [decoder decodeBoolForKey:goScoreLastCalculationHadErrorKey];

  _operationQueue = [[NSOperationQueue alloc] init];

  return self;
}

// -----------------------------------------------------------------------------
/// @brief Deallocates memory allocated by this GoScore object.
// -----------------------------------------------------------------------------
- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  self.operationQueue = nil;
  [super dealloc];
}

// -----------------------------------------------------------------------------
/// @brief Resets all score values to zero. Typically invoked before a new
/// calculation starts.
// -----------------------------------------------------------------------------
- (void) resetValues
{
  self.komi = 0;
  self.capturedByBlack = 0;
  self.capturedByWhite = 0;
  self.deadBlack = 0;
  self.deadWhite = 0;
  self.territoryBlack = 0;
  self.territoryWhite = 0;
  self.totalScoreBlack = 0;
  self.totalScoreWhite = 0;
  self.result = GoGameResultNone;
  self.numberOfMoves = 0;
  self.stonesPlayedByBlack = 0;
  self.stonesPlayedByWhite = 0;
  self.passesPlayedByBlack = 0;
  self.passesPlayedByWhite = 0;
}

// -----------------------------------------------------------------------------
// Property is documented in the header file.
// -----------------------------------------------------------------------------
- (void) setTerritoryScoringEnabled:(bool)newState
{
  if (_territoryScoringEnabled == newState)
    return;
  _territoryScoringEnabled = newState;
  NSString* notificationName;
  if (newState)
  {
    [self initializeRegions];
    self.didAskGtpEngineForDeadStones = false;
    notificationName = goScoreTerritoryScoringEnabled;
  }
  else
  {
    [self uninitializeRegions];
    notificationName = goScoreTerritoryScoringDisabled;
  }
  [self performSelector:@selector(postNotificationOnMainThread:)
               onThread:[NSThread mainThread]
             withObject:notificationName
          waitUntilDone:NO];
}

// -----------------------------------------------------------------------------
/// @brief Private helper for setTerritoryScoringEnabled.
// -----------------------------------------------------------------------------
- (void) initializeRegions
{
  NSArray* allRegions = self.game.board.regions;
  DDLogVerbose(@"%@: initializing GoBoardRegion objects, number of regions = %d", self, allRegions.count);
  for (GoBoardRegion* region in allRegions)
  {
    region.territoryColor = GoColorNone;
    region.territoryInconsistencyFound = false;
    region.deadStoneGroup = false;
    region.scoringMode = true;  // enabling scoring mode allows caching for optimized performance
  }
}

// -----------------------------------------------------------------------------
/// @brief Private helper for setTerritoryScoringEnabled.
// -----------------------------------------------------------------------------
- (void) uninitializeRegions
{
  NSArray* allRegions = self.game.board.regions;
  DDLogVerbose(@"%@: uninitializing GoBoardRegion objects, number of regions = %d", self, allRegions.count);
  for (GoBoardRegion* region in allRegions)
    region.scoringMode = false;  // forget cached values
}

// -----------------------------------------------------------------------------
/// @brief Notifies this GoScore that the board position is about to be changed.
/// Invocation of this method must be balanced by also invoking
/// didChangeBoardPosition.
///
/// If territory scoring is currently enabled, this GoScore temporarily
/// un-initializes GoGame and its associated objects so that the territory
/// scoring mode does not interfere with the board position change.
// -----------------------------------------------------------------------------
- (void) willChangeBoardPosition
{
  if (! self.territoryScoringEnabled)
    return;
  [self uninitializeRegions];
}

// -----------------------------------------------------------------------------
/// @brief Notifies this GoScore that a board position change has been
/// completed. This method must be invoked to balance a previous invocation of
/// willChangeBoardPosition.
///
/// If territory scoring is currently enabled, this GoScore re-initializes
/// GoGame and its associated objects for territory scoring mode so that a new
/// score can be calculated for the new board position.
// -----------------------------------------------------------------------------
- (void) didChangeBoardPosition
{
  if (! self.territoryScoringEnabled)
    return;
  [self initializeRegions];
  self.didAskGtpEngineForDeadStones = false;
}

// -----------------------------------------------------------------------------
/// @brief Starts calculation of a new score.
///
/// If @a waitUntilDone is false, this method returns immediately and does not
/// wait for the calculation to finish.
///
/// Observers are notified of the start and end of the calculation by the
/// notifications #goScoreCalculationStarts and #goScoreCalculationStarts which
/// are posted on the application's default NSNotificationCentre in the context
/// of the main thread.
///
/// @note This method does nothing if a scoring operation is already in
/// progress.
// -----------------------------------------------------------------------------
- (void) calculateWaitUntilDone:(bool)waitUntilDone
{
  DDLogVerbose(@"%@: calculateWaitUntilDone invoked; waitUntilDone = %d, scoringInProgress = %d, game = %@",
               self,
               waitUntilDone,
               self.scoringInProgress,
               self.game);
  if (self.scoringInProgress)
    return;
  self.scoringInProgress = true;  // notify while we're still in the main thread context

  if (waitUntilDone)
    [self doCalculate];
  else
  {
    NSInvocationOperation* operation = [[NSInvocationOperation alloc] initWithTarget:self
                                                                            selector:@selector(doCalculate)
                                                                              object:nil];
    [self.operationQueue addOperation:operation];
    [operation release];
  }
}

// -----------------------------------------------------------------------------
/// @brief Calculates a new score.
///
/// This method runs in the main thread context if calculateWaitUntilDone:()
/// was invoked with value @e true for the @e waitUntilDone argument. If the
/// argument value was @e false, though, this method runs in the context of a
/// secondary thread.
// -----------------------------------------------------------------------------
- (void) doCalculate
{
  @try
  {
    self.lastCalculationHadError = false;
    [self resetValues];

    if (self.territoryScoringEnabled)
    {
      [self askGtpEngineForDeadStones];
      bool success = [self updateTerritoryColor];
      DDLogVerbose(@"%@: updateTerritoryColor returned with result = %d", self, success);
      if (! success)
      {
        self.lastCalculationHadError = true;
        return;
      }
    }

    [self updateScoringProperties];
  }
  @finally
  {
    self.scoringInProgress = false;
  }
}

// -----------------------------------------------------------------------------
// Property is documented in the header file.
// -----------------------------------------------------------------------------
- (void) setScoringInProgress:(bool)newValue
{
  if (_scoringInProgress == newValue)
    return;
  _scoringInProgress = newValue;
  NSString* notificationName;
  if (newValue)
    notificationName = goScoreCalculationStarts;
  else
    notificationName = goScoreCalculationEnds;
  [self performSelector:@selector(postNotificationOnMainThread:)
               onThread:[NSThread mainThread]
             withObject:notificationName
          waitUntilDone:NO];
}

// -----------------------------------------------------------------------------
/// @brief Returns a nicely formatted string that reflects the overall result
/// of the current scoring information. The string can be displayed to the user.
// -----------------------------------------------------------------------------
- (NSString*) resultString
{
  if (self.lastCalculationHadError)
    return @"Error calculating score";

  switch (self.result)
  {
    case GoGameResultNone:
      return @"No score calculated yet";
    case GoGameResultBlackHasWon:
    {
      NSString* score = [NSString stringWithFractionValue:self.totalScoreBlack - self.totalScoreWhite];
      return [NSString stringWithFormat:@"Black wins by %@", score];
    }
    case GoGameResultWhiteHasWon:
    {
      NSString* score = [NSString stringWithFractionValue:self.totalScoreWhite - self.totalScoreBlack];
      return [NSString stringWithFormat:@"White wins by %@", score];
    }
    case GoGameResultTie:
      return @"Game is a tie";
    default:
    {
      DDLogError(@"%@: Unexpected GoGameResult value %d", self, self.result);
      assert(0);
      break;
    }
  }
  return @"Unknown game result";
}

// -----------------------------------------------------------------------------
/// @brief Queries the GTP engine for an initial set of dead stones. Updates
/// GoBoardRegion objects with the result of the query.
// -----------------------------------------------------------------------------
- (void) askGtpEngineForDeadStones
{
  if (! [ApplicationDelegate sharedDelegate].scoringModel.askGtpEngineForDeadStones)
    return;
  if (self.didAskGtpEngineForDeadStones)
    return;
  self.didAskGtpEngineForDeadStones = true;

  @try
  {
    self.askGtpEngineForDeadStonesInProgress = true;
    [self performSelector:@selector(postNotificationOnMainThread:)
                 onThread:[NSThread mainThread]
               withObject:askGtpEngineForDeadStonesStarts
            waitUntilDone:YES];
    GtpCommand* command = [GtpCommand command:@"final_status_list dead"];
    [command submit];
    if (command.response.status)
    {
      NSArray* deadStoneVertexList = [self parseDeadStoneGtpResponse:command.response.parsedResponse];
      for (NSString* vertex in deadStoneVertexList)
      {
        GoPoint* point = [self.game.board pointAtVertex:vertex];
        if (! [point hasStone])
        {
          DDLogError(@"%@: GTP engine reports vertex %@ is dead stone, but point %@ has no stone", self, vertex, point);
          assert(0);
          continue;
        }
        // TODO The next statement is problematic in two respects: 1) If the
        // region has more than one point, we repeatedly set it to be dead,
        // once for each vertex reported by the GTP engine. 2) We don't perform
        // any kind of check if the vertex list reported by the GTP engine
        // matches our regions.
        point.region.deadStoneGroup = true;
      }
    }
    else
    {
      DDLogError(@"%@: Querying GTP engine for initial set of dead stones failed", self);
      assert(0);
    }
  }
  @finally
  {
    self.askGtpEngineForDeadStonesInProgress = false;
    [self performSelector:@selector(postNotificationOnMainThread:)
                 onThread:[NSThread mainThread]
               withObject:askGtpEngineForDeadStonesEnds
            waitUntilDone:YES];
  }
}

// -----------------------------------------------------------------------------
/// @brief Private helper. Is invoked in the context of the main thread.
// -----------------------------------------------------------------------------
- (void) postNotificationOnMainThread:(NSString*)notificationName
{
  [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:nil];
}

// -----------------------------------------------------------------------------
/// @brief Parses @a gtpResponse, which is expected to be the response to the
/// command "final_status_list dead", for strings that denote vertexes. Returns
/// a list with all vertexes found.
// -----------------------------------------------------------------------------
- (NSArray*) parseDeadStoneGtpResponse:(NSString*)gtpResponse
{
  NSMutableArray* deadStoneVertexList = [NSMutableArray arrayWithCapacity:0];
  if (0 == gtpResponse.length)
    return deadStoneVertexList;
  NSArray* responseLines = [gtpResponse componentsSeparatedByString:@"\n"];
  for (NSString* responseLine in responseLines)
  {
    if (0 == responseLine.length)
      continue;
    NSArray* vertexList = [responseLine componentsSeparatedByString:@" "];
    for (NSString* vertex in vertexList)
    {
      if (0 == vertex.length)
        continue;
      [deadStoneVertexList addObject:vertex];
    }
  }
  return deadStoneVertexList;
}

// -----------------------------------------------------------------------------
/// @brief Toggles the status of the stone group @a stoneGroup from alive to
/// dead, or vice versa.
///
/// Once the main stone group @a stoneGroup has been updated, this method also
/// considers neighbouring regions and, if necessary, toggles the dead/alive
/// state of other stone groups to remain consistent with the logic of the game
/// rules. This feature is optional and the user can turn it off in the user
/// preferences. For details read the class documentation, section "Mark dead
/// stones intelligently".
///
/// @note Invoking this method does not change the current scoring values. The
/// client needs to separately invoke calculateWaitUntilDone:() to get the
/// updated score.
///
/// @note This method does nothing if territory scoring is not enabled on this
/// GoScore object, or if a scoring operation is already in progress.
// -----------------------------------------------------------------------------
- (void) toggleDeadStoneStateOfGroup:(GoBoardRegion*)stoneGroup
{
  if (! self.territoryScoringEnabled)
    return;
  if (self.scoringInProgress)
    return;
  if (! [stoneGroup isStoneGroup])
    return;

  bool markDeadStonesIntelligently = [ApplicationDelegate sharedDelegate].scoringModel.markDeadStonesIntelligently;

  // We use this array like a queue: We add GoBoardRegion objects to it that
  // need to be toggled, and we loop until the queue is empty. In each iteration
  // new GoBoardRegion objects may be added to the queue which will cause the
  // loop to run longer.
  NSMutableArray* stoneGroupsToToggle = [NSMutableArray arrayWithCapacity:0];
  // And this array is the guard that prevents an infinite loop: Whenever a
  // GoBoardRegion object is processed by the loop, it puts the processed object
  // into this array. Before the loop starts processing a GoBoardRegion object,
  // though, it looks into the array to see if the object has already been
  // processed in an earlier iteration.
  NSMutableArray* regionsAlreadyProcessed = [NSMutableArray arrayWithCapacity:0];

  [stoneGroupsToToggle addObject:stoneGroup];
  [regionsAlreadyProcessed addObject:stoneGroup];
  while (stoneGroupsToToggle.count > 0)
  {
    GoBoardRegion* stoneGroupToToggle = [stoneGroupsToToggle objectAtIndex:0];
    [stoneGroupsToToggle removeObjectAtIndex:0];

    bool newDeadState = ! stoneGroupToToggle.deadStoneGroup;
    stoneGroupToToggle.deadStoneGroup = newDeadState;
    enum GoColor colorOfStoneGroupToToggle = [stoneGroupToToggle color];

    // If the user has decided that he does not need any help with toggling,
    // we can abort the whole process now
    if (! markDeadStonesIntelligently)
      break;

    // Collect stone groups that are either directly adjacent to the stone
    // group we just toggled ("once removed"), or separated from it by an
    // intermediate empty region ("twice removed").
    NSMutableArray* adjacentStoneGroupsToExamine = [NSMutableArray arrayWithCapacity:0];
    for (GoBoardRegion* adjacentRegionOnceRemoved in [stoneGroupToToggle adjacentRegions])
    {
      if ([regionsAlreadyProcessed containsObject:adjacentRegionOnceRemoved])
        continue;
      [regionsAlreadyProcessed addObject:adjacentRegionOnceRemoved];
      if ([adjacentRegionOnceRemoved color] != GoColorNone)
        [adjacentStoneGroupsToExamine addObject:adjacentRegionOnceRemoved];
      else
      {
        for (GoBoardRegion* adjacentRegionTwiceRemoved in [adjacentRegionOnceRemoved adjacentRegions])
        {
          if ([regionsAlreadyProcessed containsObject:adjacentRegionTwiceRemoved])
            continue;
          [regionsAlreadyProcessed addObject:adjacentRegionTwiceRemoved];
          if ([adjacentRegionTwiceRemoved color] == GoColorNone)
          {
            DDLogError(@"%@: Inconsistency - regions adjacent to an empty region cannot be empty, too, adjacent empty region = %@", self, adjacentRegionTwiceRemoved);
            assert(0);
          }
          else
            [adjacentStoneGroupsToExamine addObject:adjacentRegionTwiceRemoved];
        }
      }
    }

    // Now examine the collected stone groups and, if necessary, toggle their
    // dead/alive state:
    // - Stone groups of the same color need to get into the same state
    // - In theory, stone groups of the opposing color need to get into the
    //   opposite state, but doing this has too much effect, so for the moment
    //   we ignore the opposing color
    // See the "Mark dead stones intelligently" section in the class
    // documentation for details.
    for (GoBoardRegion* adjacentStoneGroupToExamine in adjacentStoneGroupsToExamine)
    {
      if (! [adjacentStoneGroupToExamine isStoneGroup])
      {
        DDLogError(@"%@: Error in previous loop, we should have collected only stone groups, adjacent empty region = %@", self, adjacentStoneGroupToExamine);
        assert(0);
        continue;
      }
      enum GoColor colorOfAdjacentStoneGroupToExamine = [adjacentStoneGroupToExamine color];
      if (colorOfAdjacentStoneGroupToExamine == colorOfStoneGroupToToggle)
      {
        if (adjacentStoneGroupToExamine.deadStoneGroup != newDeadState)
          [stoneGroupsToToggle addObject:adjacentStoneGroupToExamine];
      }
    }
  }
}

// -----------------------------------------------------------------------------
/// @brief (Re)Calculates the territory color of all GoBoardRegion objects.
/// Returns true if calculation was successful, false if not.
///
/// This method looks at the @e deadStoneGroup property of GoBoardRegion
/// objects. For details see the class documentation, paragraph "Determining
/// territory color".
///
/// Initial dead stones are set up by askGtpEngineForDeadStones(). User
/// interaction during scoring invokes toggleDeadStoneStateOfGroup:() to add
/// more dead stones, or turn them back to alive.
// -----------------------------------------------------------------------------
- (bool) updateTerritoryColor
{
  // Regions that are truly empty, i.e. that do not have dead stones
  NSMutableArray* emptyRegions = [NSMutableArray arrayWithCapacity:0];

  // Pass 1: Set territory colors for stone groups. This is easy and can be
  // done both for groups that are alive and dead. While we are at it, we can
  // also collect empty regions, which will be processed in pass 2.
  NSArray* allRegions = self.game.board.regions;
  for (GoBoardRegion* region in allRegions)
  {
    if (! [region isStoneGroup])
    {
      // Setting territory color here is temporary, the final color will be
      // determined in pass 2. We still need to do it, though, to erase traces
      // from a previous scoring calculation.
      region.territoryColor = GoColorNone;
      [emptyRegions addObject:region];
    }
    else
    {
      // If the group is alive, it belongs to the territory of the color who
      // played the stones in the group. This is important only for area
      // scoring.
      if (! region.deadStoneGroup)
        region.territoryColor = [region color];
      // If the group is dead, it belongs to the territory of the opposing color
      else
      {
        switch ([region color])
        {
          case GoColorBlack:
            region.territoryColor = GoColorWhite;
            break;
          case GoColorWhite:
            region.territoryColor = GoColorBlack;
            break;
          default:
            DDLogError(@"%@: Stone groups must be either black or white, region %@ has color %d", self, region, [region color]);
            return false;
        }
      }
    }
  }

  // Pass 2: Process empty regions. Here we examine the stone groups adjacent
  // to each empty region to determine the empty region's final territory color.
  for (GoBoardRegion* emptyRegion in emptyRegions)
  {
    bool aliveSeen = false;
    bool blackAliveSeen = false;
    bool whiteAliveSeen = false;
    bool deadSeen = false;
    bool blackDeadSeen = false;
    bool whiteDeadSeen = false;
    for (GoBoardRegion* adjacentRegion in [emptyRegion adjacentRegions])
    {
      if (! [adjacentRegion isStoneGroup])
      {
        DDLogError(@"%@: Regions adjacent to an empty region can only be stone groups, adjacent region = %@", self, adjacentRegion);
        return false;
      }
      if (adjacentRegion.deadStoneGroup)
      {
        deadSeen = true;
        switch ([adjacentRegion color])
        {
          case GoColorBlack:
            blackDeadSeen = true;
            break;
          case GoColorWhite:
            whiteDeadSeen = true;
            break;
          default:
            DDLogError(@"%@: Stone groups must be either black or white, adjacent dead stone group region %@ has color %d", self, adjacentRegion, [adjacentRegion color]);
            return false;  // error! stone group must be either black or white
        }
      }
      else
      {
        aliveSeen = true;
        switch ([adjacentRegion color])
        {
          case GoColorBlack:
            blackAliveSeen = true;
            break;
          case GoColorWhite:
            whiteAliveSeen = true;
            break;
          default:
            DDLogError(@"%@: Stone groups must be either black or white, adjacent alive stone group region %@ has color %d", self, adjacentRegion, [adjacentRegion color]);
            return false;
        }
      }
    }

    bool territoryInconsistencyFound = false;
    enum GoColor territoryColor = GoColorNone;
    if (! deadSeen)
    {
      if (! aliveSeen)  // ok, empty board
        territoryColor = GoColorNone;
      else
      {
        if (blackAliveSeen && whiteAliveSeen)  // ok, neutral territory
          territoryColor = GoColorNone;
        else  // ok, only one color has been seen, and all groups were alive
        {
          if (blackAliveSeen)
            territoryColor = GoColorBlack;
          else
            territoryColor = GoColorWhite;
        }
      }
    }
    else
    {
      if (blackDeadSeen)
      {
        if (blackAliveSeen)  // rules violation! cannot see both dead and alive stones of the same color
          territoryInconsistencyFound = true;
        else if (whiteDeadSeen)  // rules violation! cannot see dead stones of both colors
          territoryInconsistencyFound = true;
        else                     // ok, only dead stones of one color seen (we don't care whether the opposing color has alive stones)
          territoryColor = GoColorWhite;
      }
      else  // repeat of the block above, but for the opposing color
      {
        if (whiteAliveSeen)
          territoryInconsistencyFound = true;
        else if (blackDeadSeen)
          territoryInconsistencyFound = true;
        else
          territoryColor = GoColorBlack;
      }
    }

    emptyRegion.territoryColor = territoryColor;
    emptyRegion.territoryInconsistencyFound = territoryInconsistencyFound;
  }

  return true;
}

// -----------------------------------------------------------------------------
/// @brief (Re)Calculates the scoring and move statistics properties of this
/// GoScore object.
///
/// If territory scoring is enabled, this method requires that the
/// @e deadStoneGroup and @e territoryColor properties of GoBoardRegion objects
/// are correct and up-to-date.
// -----------------------------------------------------------------------------
- (void) updateScoringProperties
{
  // Komi
  self.komi = self.game.komi;

  // Captured stones (up to the current board position) and move statistics (for
  // the entire game)
  self.numberOfMoves = 0;
  GoMove* currentBoardPositionMove = self.game.boardPosition.currentMove;
  bool loopHasPassedCurrentBoardPosition = false;
  GoMove* move = self.game.lastMove;
  while (move != nil)
  {
    if (! loopHasPassedCurrentBoardPosition)
    {
      if (move == currentBoardPositionMove)
        loopHasPassedCurrentBoardPosition = true;
    }

    self.numberOfMoves++;
    bool moveByBlack = move.player.black;
    switch (move.type)
    {
      case GoMoveTypePlay:
      {
        if (moveByBlack)
        {
          if (loopHasPassedCurrentBoardPosition)
            self.capturedByBlack += move.capturedStones.count;
          self.stonesPlayedByBlack++;
        }
        else
        {
          if (loopHasPassedCurrentBoardPosition)
            self.capturedByWhite += move.capturedStones.count;
          self.stonesPlayedByWhite++;
        }
        break;
      }
      case GoMoveTypePass:
      {
        if (moveByBlack)
          self.passesPlayedByBlack++;
        else
          self.passesPlayedByWhite++;
        break;
      }
      default:
        break;
    }
    move = move.previous;
  }

  // Territory & dead stones (for current board position)
  if (self.territoryScoringEnabled)
  {
    NSArray* allRegions = self.game.board.regions;
    for (GoBoardRegion* region in allRegions)
    {
      int regionSize = [region size];
      // Territory: We only count dead stones and empty intersections
      if (region.deadStoneGroup || ! [region isStoneGroup])
      {
        switch (region.territoryColor)
        {
          case GoColorBlack:
            self.territoryBlack += regionSize;
            break;
          case GoColorWhite:
            self.territoryWhite += regionSize;
            break;
          default:
            break;
        }
      }

      // Dead stones
      if (region.deadStoneGroup)
      {
        switch ([region color])
        {
          case GoColorBlack:
            self.deadBlack += regionSize;
            break;
          case GoColorWhite:
            self.deadWhite += regionSize;
            break;
          default:
            break;
        }
      }
    }
  }

  // Total score
  self.totalScoreBlack = self.capturedByBlack + self.deadWhite + self.territoryBlack;
  self.totalScoreWhite = self.komi + self.capturedByWhite + self.deadBlack + self.territoryWhite;

  // Final result
  if (self.totalScoreBlack > self.totalScoreWhite)
    self.result = GoGameResultBlackHasWon;
  else if (self.totalScoreWhite > self.totalScoreBlack)
    self.result = GoGameResultWhiteHasWon;
  else
    self.result = GoGameResultTie;
}


// -----------------------------------------------------------------------------
/// @brief NSCoding protocol method.
// -----------------------------------------------------------------------------
- (void) encodeWithCoder:(NSCoder*)encoder
{
  [encoder encodeInt:nscodingVersion forKey:nscodingVersionKey];
  [encoder encodeBool:self.territoryScoringEnabled forKey:goScoreTerritoryScoringEnabledKey];
  [encoder encodeBool:self.scoringInProgress forKey:goScoreScoringInProgressKey];
  [encoder encodeBool:self.askGtpEngineForDeadStonesInProgress forKey:goScoreAskGtpEngineForDeadStonesInProgressKey];
  [encoder encodeDouble:self.komi forKey:goScoreKomiKey];
  [encoder encodeInt:self.capturedByBlack forKey:goScoreCapturedByBlackKey];
  [encoder encodeInt:self.capturedByWhite forKey:goScoreCapturedByWhiteKey];
  [encoder encodeInt:self.deadBlack forKey:goScoreDeadBlackKey];
  [encoder encodeInt:self.deadWhite forKey:goScoreDeadWhiteKey];
  [encoder encodeInt:self.territoryBlack forKey:goScoreTerritoryBlackKey];
  [encoder encodeInt:self.territoryWhite forKey:goScoreTerritoryWhiteKey];
  [encoder encodeInt:self.totalScoreBlack forKey:goScoreTotalScoreBlackKey];
  [encoder encodeDouble:self.totalScoreWhite forKey:goScoreTotalScoreWhiteKey];
  [encoder encodeInt:self.result forKey:goScoreResultKey];
  [encoder encodeInt:self.numberOfMoves forKey:goScoreNumberOfMovesKey];
  [encoder encodeInt:self.stonesPlayedByBlack forKey:goScoreStonesPlayedByBlackKey];
  [encoder encodeInt:self.stonesPlayedByWhite forKey:goScoreStonesPlayedByWhiteKey];
  [encoder encodeInt:self.passesPlayedByBlack forKey:goScorePassesPlayedByBlackKey];
  [encoder encodeInt:self.passesPlayedByWhite forKey:goScorePassesPlayedByWhiteKey];
  [encoder encodeObject:self.game forKey:goScoreGameKey];
  [encoder encodeBool:self.didAskGtpEngineForDeadStones forKey:goScoreDidAskGtpEngineForDeadStonesKey];
  [encoder encodeBool:self.lastCalculationHadError forKey:goScoreLastCalculationHadErrorKey];
}

@end
