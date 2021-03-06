// -----------------------------------------------------------------------------
// Copyright 2013 Patrick Näf (herzbube@herzbube.ch)
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
#import "BoardPositionView.h"
#import "BoardPositionViewMetrics.h"
#import "../../go/GoGame.h"
#import "../../go/GoMove.h"
#import "../../go/GoMoveModel.h"
#import "../../go/GoPlayer.h"
#import "../../go/GoPoint.h"
#import "../../go/GoVertex.h"
#import "../../utility/NSStringAdditions.h"
#import "../../utility/UIColorAdditions.h"

// System includes
#import <QuartzCore/QuartzCore.h>


// -----------------------------------------------------------------------------
/// @brief Class extension with private properties for BoardPositionView.
// -----------------------------------------------------------------------------
@interface BoardPositionView()
@property(nonatomic, assign) BoardPositionViewMetrics* viewMetrics;
@end


@implementation BoardPositionView

// -----------------------------------------------------------------------------
/// @brief Initializes a BoardPositionView object that represents the board
/// position identified by @a boardPosition and uses @a viewMetrics to obtain
/// sizes and other attributes that define the view's layout.
///
/// @note This is the designated initializer of BoardPositionView.
// -----------------------------------------------------------------------------
- (id) initWithBoardPosition:(int)boardPosition viewMetrics:(BoardPositionViewMetrics*)viewMetrics
{
  // Call designated initializer of superclass (UIView)
  self = [super initWithFrame:CGRectZero];
  if (! self)
    return nil;
  _boardPosition = boardPosition;  // don't use self, we don't want to trigger the setter
  _currentBoardPosition = false;    // ditto
  self.viewMetrics = viewMetrics;
  self.bounds = self.viewMetrics.boardPositionViewBounds;
  return self;
}

// -----------------------------------------------------------------------------
/// @brief Deallocates memory allocated by this BoardPositionView
/// object.
// -----------------------------------------------------------------------------
- (void) dealloc
{
  self.viewMetrics = nil;
  [super dealloc];
}

// -----------------------------------------------------------------------------
/// @brief This overrides the superclass implementation.
// -----------------------------------------------------------------------------
- (void) layoutSubviews
{
  [super layoutSubviews];

  for (UIView* subview in self.subviews)
    [subview removeFromSuperview];
  self.backgroundColor = [UIColor clearColor];
  if (-1 == self.boardPosition)
    return;

  GoMove* move = nil;
  if (0 == self.boardPosition)
  {
    NSString* labelText = [self labelTextForFirstBoardPosition];
    UILabel* label = [self labelWithText:labelText];
    [self addSubview:label];
  }
  else
  {
    int moveIndex = self.boardPosition - 1;
    move = [[GoGame sharedGame].moveModel moveAtIndex:moveIndex];
    NSString* labelText = [self labelTextForMove:move moveIndex:moveIndex];
    UILabel* label = [self labelWithText:labelText];
    UIImageView* stoneImageView = [self stoneImageViewForMove:move];
    [self addSubview:label];
    [self addSubview:stoneImageView];
    NSString* capturedStonesLabelText = [self capturedStonesLabelTextForMove:move];
    if (capturedStonesLabelText)
    {
      UILabel* capturedStonesLabel = [self capturedStonesLabelWithText:capturedStonesLabelText];
      [self addSubview:capturedStonesLabel];
    }
  }
  [self setupBackgroundColorForMove:move];
}

// -----------------------------------------------------------------------------
/// @brief This is an internal helper for layoutSubviews().
// -----------------------------------------------------------------------------
- (NSString*) labelTextForMove:(GoMove*)move moveIndex:(int)moveIndex
{
  NSString* vertexString;
  if (GoMoveTypePlay == move.type)
    vertexString = move.point.vertex.string;
  else
    vertexString = @"Pass";
  int moveNumber = moveIndex + 1;
  return [NSString stringWithFormat:@"%d\n%@", moveNumber, vertexString];
}

// -----------------------------------------------------------------------------
/// @brief This is an internal helper for layoutSubviews().
// -----------------------------------------------------------------------------
- (NSString*) labelTextForFirstBoardPosition
{
  GoGame* game = [GoGame sharedGame];
  NSString* komiString = [NSString stringWithKomi:game.komi numericZeroValue:true];
  return [NSString stringWithFormat:@"H: %1d\nK: %@", game.handicapPoints.count, komiString];
}

// -----------------------------------------------------------------------------
/// @brief This is an internal helper for layoutSubviews().
// -----------------------------------------------------------------------------
- (UILabel*) labelWithText:(NSString*)labelText
{
  UILabel* label = [[[UILabel alloc] initWithFrame:self.viewMetrics.labelFrame] autorelease];
  label.font = [UIFont systemFontOfSize:self.viewMetrics.boardPositionViewFontSize];
  [label setNumberOfLines:self.viewMetrics.labelNumberOfLines];
  label.backgroundColor = [UIColor clearColor];
  label.text = labelText;
  // Size-to-fit because for board position 0 the label text is wider than
  // labelFrame.size.width (but that's OK since for board position 0 the view
  // does not display a stone image)
  if (0 == self.boardPosition)
    [label sizeToFit];
  return label;
}

// -----------------------------------------------------------------------------
/// @brief This is an internal helper for layoutSubviews().
// -----------------------------------------------------------------------------
- (UIImageView*) stoneImageViewForMove:(GoMove*)move
{
  UIImage* stoneImage;
  if (move.player.black)
    stoneImage = self.viewMetrics.blackStoneImage;
  else
    stoneImage = self.viewMetrics.whiteStoneImage;
  UIImageView* stoneImageView = [[[UIImageView alloc] initWithImage:stoneImage] autorelease];
  stoneImageView.frame = self.viewMetrics.stoneImageViewFrame;
  return stoneImageView;
}

// -----------------------------------------------------------------------------
/// @brief This is an internal helper for layoutSubviews().
// -----------------------------------------------------------------------------
- (NSString*) capturedStonesLabelTextForMove:(GoMove*)move
{
  if (GoMoveTypePass == move.type)
    return nil;
  int numberOfCapturedStones = move.capturedStones.count;
  if (0 == numberOfCapturedStones)
    return nil;
  return [NSString stringWithFormat:@"%d", numberOfCapturedStones];
}

// -----------------------------------------------------------------------------
/// @brief This is an internal helper for layoutSubviews().
// -----------------------------------------------------------------------------
- (UILabel*) capturedStonesLabelWithText:(NSString*)labelText
{
  UILabel* label = [[[UILabel alloc] initWithFrame:self.viewMetrics.capturedStonesLabelFrame] autorelease];
  label.font = [UIFont systemFontOfSize:self.viewMetrics.boardPositionViewFontSize];
  [label setNumberOfLines:1];
  label.backgroundColor = [UIColor clearColor];
  label.text = labelText;
  label.textAlignment = NSTextAlignmentRight;
  label.textColor = [UIColor redColor];
  return label;
}

// -----------------------------------------------------------------------------
/// @brief This is an internal helper for layoutSubviews().
// -----------------------------------------------------------------------------
- (void) setupBackgroundColorForMove:(GoMove*)move
{
  if (self.currentBoardPosition)
  {
    self.backgroundColor = [UIColor colorWithRed:0.0f
                                           green:0.667f
                                            blue:1.0f
                                           alpha:1.0f];
  }
  else if (0 == self.boardPosition)
  {
    if (0 == [GoGame sharedGame].handicapPoints.count)
      self.backgroundColor = [UIColor lightBlueGrayColor];
    else
      self.backgroundColor = [UIColor whiteColor];
  }
  else
  {
    if (move.player.black)
      self.backgroundColor = [UIColor whiteColor];
    else
      self.backgroundColor = [UIColor lightBlueGrayColor];
  }
}

// -----------------------------------------------------------------------------
// Property is documented in the header file.
// -----------------------------------------------------------------------------
- (void) setBoardPosition:(int)newValue
{
  if (_boardPosition == newValue)
    return;
  _boardPosition = newValue;
  [self setNeedsLayout];
}

// -----------------------------------------------------------------------------
// Property is documented in the header file.
// -----------------------------------------------------------------------------
- (void) setCurrentBoardPosition:(bool)newValue
{
  if (_currentBoardPosition == newValue)
    return;
  _currentBoardPosition = newValue;
  [self setNeedsLayout];
}

@end
