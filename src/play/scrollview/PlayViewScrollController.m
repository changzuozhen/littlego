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
#import "PlayViewScrollController.h"
#import "../PlayView.h"
#import "../PlayViewModel.h"
#import "../../main/ApplicationDelegate.h"

// -----------------------------------------------------------------------------
/// @brief Class extension with private methods for PlayViewScrollController.
// -----------------------------------------------------------------------------
@interface PlayViewScrollController()

@property(nonatomic, assign) UIScrollView* playViewScrollView;
@property(nonatomic, assign) PlayView* playView;
@property(nonatomic, assign) PlayViewModel* playViewModel;
/// @brief The overall zoom scale currently in use for drawing the Play view.
/// At zoom scale value 1.0 the entire board is visible.
@property(nonatomic, assign) CGFloat currentAbsoluteZoomScale;
@property(nonatomic, assign) CGSize playViewOriginalSize;
@end



@implementation PlayViewScrollController

// -----------------------------------------------------------------------------
/// @brief Initializes a PlayViewScrollController object that manages
/// @a scrollView and @a playView.
///
/// @note This is the designated initializer of PlayViewScrollController.
// -----------------------------------------------------------------------------
- (id) initWithScrollView:(UIScrollView*)scrollView playView:(PlayView*)playView
{
  // Call designated initializer of superclass (NSObject)
  self = [super init];
  if (! self)
    return nil;
  self.playViewScrollView = scrollView;
  self.playView = playView;
  self.playViewModel = [ApplicationDelegate sharedDelegate].playViewModel;
  self.playViewOriginalSize = self.playView.frame.size;
  [self setupScrollViews];
  [self.playViewModel addObserver:self forKeyPath:@"maximumZoomScale" options:0 context:NULL];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(deviceOrientationChanged:)
                                               name:UIDeviceOrientationDidChangeNotification
                                             object:nil];
  return self;
}

// -----------------------------------------------------------------------------
/// @brief Deallocates memory allocated by this PlayViewScrollController object.
// -----------------------------------------------------------------------------
- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self.playViewModel removeObserver:self forKeyPath:@"maximumZoomScale"];
  self.playViewModel = nil;
  [super dealloc];
}

// -----------------------------------------------------------------------------
/// @brief Private helper for the initializer.
// -----------------------------------------------------------------------------
- (void) setupScrollViews
{
  self.playViewScrollView.delegate = self;
  // Even though these scroll views do not scroll or zoom interactively, we
  // still need to become their delegate so that we can change their zoomScale
  // property. If we don't do this, then changing the zoomScale will have no
  // effect, i.e. the property will always remain at 1.0. This is because
  // UIScrollView requires a delegate that it can query with
  // viewForZoomingInScrollView: for all zoom-related operations (such as
  // changing the zoomScale).
  self.playView.coordinateLabelsLetterViewScrollView.delegate = self;
  self.playView.coordinateLabelsNumberViewScrollView.delegate = self;

  self.playViewScrollView.zoomScale = 1.0f;
  self.playViewScrollView.minimumZoomScale = 1.0f;
  self.playViewScrollView.maximumZoomScale = self.playViewModel.maximumZoomScale;
  [self synchronizeZoomScale:self.playViewScrollView.zoomScale
            minimumZoomScale:self.playViewScrollView.minimumZoomScale
            maximumZoomScale:self.playViewScrollView.maximumZoomScale];

  NSLog(@"setup: content size w = %f, h = %f",
        self.playViewScrollView.contentSize.width, self.playViewScrollView.contentSize.height);

  self.currentAbsoluteZoomScale = 1.0f;
}

// -----------------------------------------------------------------------------
/// @brief Responds to UIDeviceOrientationDidChangeNotification.
// -----------------------------------------------------------------------------
- (void) deviceOrientationChanged:(NSNotification*)notification
{
  // TODO xxx The view may be zoomed when this notification occurs, in which
  // case we will get the wrong size. A possible solution could be to have a
  // transparent view that is set up with the original PlayView size and is
  // then left untouched except for obtaining its sizes after it is rotated
  // by the system. This is an incredibly clunky solution, though :-(
  self.playViewOriginalSize = self.playView.frame.size;
}

// -----------------------------------------------------------------------------
/// @brief UIScrollViewDelegate protocol method.
// -----------------------------------------------------------------------------
- (void) scrollViewDidScroll:(UIScrollView*)scrollView
{
  // Only synchronize if the Play view scroll is the trigger. Coordinate label
  // scroll views are the trigger when their content offset is synchronized
  // because changing the content offset counts as scrolling.
  if (scrollView != self.playViewScrollView)
    return;
  // Coordinate label scroll views are not visible during zooming, so we don't
  // need to synchronize
  if (! scrollView.zooming)
    [self synchronizeContentOffset:scrollView.contentOffset];
}

// -----------------------------------------------------------------------------
/// @brief UIScrollViewDelegate protocol method.
// -----------------------------------------------------------------------------
- (UIView*) viewForZoomingInScrollView:(UIScrollView*)scrollView
{
  if (scrollView == self.playViewScrollView)
    return self.playView;
  else if (scrollView == self.playView.coordinateLabelsLetterViewScrollView)
    return self.playView.coordinateLabelsLetterView;
  else if (scrollView == self.playView.coordinateLabelsNumberViewScrollView)
    return self.playView.coordinateLabelsNumberView;
  else
    return nil;
}

// -----------------------------------------------------------------------------
/// @brief UIScrollViewDelegate protocol method.
// -----------------------------------------------------------------------------
- (void) scrollViewWillBeginZooming:(UIScrollView*)scrollView withView:(UIView*)view
{
  // Temporarily hide coordinate label views while a zoom operation is in
  // progress. Synchronizing coordinate label views' zoom scale, content offset
  // and frame size while the zoom operation is in progress is a lot of effort,
  // and even though the views are zoomed formally correct the end result looks
  // like shit (because the labels are not part of the Play view they zoom
  // differently). So instead of trying hard and failing we just dispense with
  // the effort.
  self.playView.coordinateLabelsLetterViewScrollView.hidden = YES;
  self.playView.coordinateLabelsNumberViewScrollView.hidden = YES;
}

// -----------------------------------------------------------------------------
/// @brief UIScrollViewDelegate protocol method.
// -----------------------------------------------------------------------------
- (void) scrollViewDidEndZooming:(UIScrollView*)scrollView withView:(UIView*)view atScale:(float)scale
{
  // Determine scroll view properties that we need to re-apply after the zoom
  // scale is reset to 1.0. At this point we also make sure that rounding
  // errors do not cause the minimum/maximum zoom scales to be exceeded
  CGFloat newMinimumZoomScale;
  CGFloat newMaximumZoomScale;
  CGPoint newContentOffset;
  CGSize newContentSize;
  self.currentAbsoluteZoomScale *= scale;
  if (self.currentAbsoluteZoomScale < 1.0)
  {
    self.currentAbsoluteZoomScale = 1.0;
    newMinimumZoomScale = 1.0;
    newMaximumZoomScale = self.playViewModel.maximumZoomScale;
    newContentOffset.x = 0.0;
    newContentOffset.y = 0.0;
    newContentSize = self.playViewOriginalSize;
  }
  else if (self.currentAbsoluteZoomScale > self.playViewModel.maximumZoomScale)
  {
    self.currentAbsoluteZoomScale = self.playViewModel.maximumZoomScale;
    newMinimumZoomScale = 1.0 / self.playViewModel.maximumZoomScale;
    newMaximumZoomScale = 1.0;
    newContentSize.width = self.playViewOriginalSize.width * self.playViewModel.maximumZoomScale;
    newContentSize.height = self.playViewOriginalSize.height * self.playViewModel.maximumZoomScale;
    newContentOffset = scrollView.contentOffset;
    if (newContentOffset.x + scrollView.frame.size.width > newContentSize.width)
      newContentOffset.x = newContentSize.width - scrollView.frame.size.width;
    if (newContentOffset.y + scrollView.frame.size.height > newContentSize.height)
      newContentOffset.y = newContentSize.height - scrollView.frame.size.height;
  }
  else
  {
    newMinimumZoomScale = scrollView.minimumZoomScale / scale;
    newMaximumZoomScale = scrollView.maximumZoomScale / scale;
    newContentOffset = scrollView.contentOffset;
    newContentSize = scrollView.contentSize;
  }
  DDLogVerbose(@"scrollViewDidEndZooming: new overall zoom scale = %f", self.currentAbsoluteZoomScale);

  // Remember content offset and size so that we can re-apply them after we
  // reset the zoom scale to 1.0
/*xxx
  CGPoint contentOffset = scrollView.contentOffset;
  CGSize contentSize = scrollView.contentSize;
  DDLogVerbose(@"scrollViewDidEndZooming: new content size = %f / %f ",
               contentSize.width, contentSize.height);
*/

  // Big change here: This resets the scroll view's contentSize and
  // contentOffset, and also the PlayView's frame, bounds and transform
  // properties
  scrollView.zoomScale = 1.0f;
  // Adjust the minimum and maximum zoom scale so that the user cannot zoom
  // in/out more than originally intended
  scrollView.minimumZoomScale = newMinimumZoomScale;
  scrollView.maximumZoomScale = newMaximumZoomScale;
  DDLogVerbose(@"scrollViewDidEndZooming: new minimumZoomScale = %f, maximumZoomScale = %f",
               scrollView.minimumZoomScale, scrollView.maximumZoomScale);

  // Re-apply some property values that were changed when the zoom scale was
  // reset to 1.0
  scrollView.contentSize = newContentSize;
  [scrollView setContentOffset:newContentOffset animated:NO];
  self.playView.frame = CGRectMake(0, 0, newContentSize.width, newContentSize.height);

  [self synchronizeZoomScale:self.playViewScrollView.zoomScale
            minimumZoomScale:self.playViewScrollView.minimumZoomScale
            maximumZoomScale:self.playViewScrollView.maximumZoomScale];
  [self synchronizeContentOffset:newContentOffset];
  // At this point we should also update content size and frame changes. We
  // don't do so because PlayView already takes care of all this for us.
  self.playView.coordinateLabelsLetterViewScrollView.hidden = NO;
  self.playView.coordinateLabelsNumberViewScrollView.hidden = NO;

  // Finally, trigger the view/layer to redraw their content
  [self.playView setNeedsLayout];
}

// -----------------------------------------------------------------------------
/// @brief Responds to KVO notifications.
// -----------------------------------------------------------------------------
- (void) observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
  PlayViewModel* playViewModel = [ApplicationDelegate sharedDelegate].playViewModel;
  if (object == playViewModel)
  {
    if ([keyPath isEqualToString:@"maximumZoomScale"])
    {
      if (self.currentAbsoluteZoomScale <= playViewModel.maximumZoomScale)
      {
        CGFloat newRelativeMaximumZoomScale = playViewModel.maximumZoomScale / self.currentAbsoluteZoomScale;
        self.playViewScrollView.maximumZoomScale = newRelativeMaximumZoomScale;
      }
      else
      {
        // The Play view is currently zoomed in more than the new maximum zoom
        // scale allows. The goal is to adjust the current zoom scale, and all
        // depending metrics, to the new maximum.
        CGFloat newAbsoluteZoomScale = playViewModel.maximumZoomScale;
        CGFloat factor = self.currentAbsoluteZoomScale / newAbsoluteZoomScale;
        CGFloat oldAbsoluteZoomScale = self.currentAbsoluteZoomScale;
        self.currentAbsoluteZoomScale = newAbsoluteZoomScale;

        // Make sure that after we are finished the user cannot zoom in any
        // further
        if (self.playViewScrollView.maximumZoomScale > 1.0f)
          self.playViewScrollView.maximumZoomScale = 1.0f;

        // Adjust the relative minimum zoom scale
        CGFloat oldRelativeMinimumZoomScale = self.playViewScrollView.minimumZoomScale;
        self.playViewScrollView.minimumZoomScale = factor * oldRelativeMinimumZoomScale;

        // Adjust content offset, content size and Play view frame size
        CGPoint newContentOffset = self.playViewScrollView.contentOffset;
        newContentOffset.x /= factor;
        newContentOffset.y /= factor;
        self.playViewScrollView.contentOffset = newContentOffset;
        CGSize newContentSize = self.playViewScrollView.contentSize;
        newContentSize.width /= factor;
        newContentSize.height /= factor;
        self.playViewScrollView.contentSize = newContentSize;
        self.playView.frame = CGRectMake(0, 0, newContentSize.width, newContentSize.height);

        DDLogInfo(@"%@: Adjusting old zoom scale %f to new maximum %f",
                  self, oldAbsoluteZoomScale, newAbsoluteZoomScale);
        DDLogVerbose(@"%@: Old/new relative minimum zoom scale = %f / %f",
                     self, oldRelativeMinimumZoomScale, self.playViewScrollView.minimumZoomScale);
        DDLogVerbose(@"%@: New content offset = %f / %f ",
                     self, newContentOffset.x, newContentOffset.y);
        DDLogVerbose(@"%@: New content size = %f / %f ",
                     self, newContentSize.width, newContentSize.height);

        [self.playView setNeedsLayout];
      }
    }
  }
}

// -----------------------------------------------------------------------------
/// @brief Internal helper for synchronizing scroll view.
// -----------------------------------------------------------------------------
- (void) synchronizeContentOffset:(CGPoint)contentOffset
{
  CGPoint coordinateLabelsLetterViewScrollViewContentOffset = self.playView.coordinateLabelsLetterViewScrollView.contentOffset;
  coordinateLabelsLetterViewScrollViewContentOffset.x = contentOffset.x;
  self.playView.coordinateLabelsLetterViewScrollView.contentOffset = coordinateLabelsLetterViewScrollViewContentOffset;
  CGPoint coordinateLabelsNumberViewScrollViewContentOffset = self.playView.coordinateLabelsNumberViewScrollView.contentOffset;
  coordinateLabelsNumberViewScrollViewContentOffset.y = contentOffset.y;
  self.playView.coordinateLabelsNumberViewScrollView.contentOffset = coordinateLabelsNumberViewScrollViewContentOffset;
}

// -----------------------------------------------------------------------------
/// @brief Internal helper for synchronizing scroll view.
// -----------------------------------------------------------------------------
- (void) synchronizeZoomScale:(CGFloat)zoomScale
             minimumZoomScale:(CGFloat)minimumZoomScale
             maximumZoomScale:(CGFloat)maximumZoomScale
{
  self.playView.coordinateLabelsLetterViewScrollView.zoomScale = zoomScale;
  self.playView.coordinateLabelsLetterViewScrollView.minimumZoomScale = minimumZoomScale;
  self.playView.coordinateLabelsLetterViewScrollView.maximumZoomScale = maximumZoomScale;
  self.playView.coordinateLabelsNumberViewScrollView.zoomScale = zoomScale;
  self.playView.coordinateLabelsNumberViewScrollView.minimumZoomScale = minimumZoomScale;
  self.playView.coordinateLabelsNumberViewScrollView.maximumZoomScale = maximumZoomScale;
}

@end
