//
//  LXNotePopUpViewController.h
//  EvePopViewController
//
//  Created by Harry Duan on 8/1/16.
//  Copyright © 2016 Harry_Duan. All rights reserved.
//

#import <UIKit/UIKit.h>


@class LXNotePopUpViewController;

typedef void(^LXNotePopUpSaveHandler)(LXNotePopUpViewController *Self, NSString *noteText);

@protocol ModalViewControllerDelegate <NSObject>

- (void)modalViewControllerDidClickDismissButton: (LXNotePopUpViewController *)viewController;

@end


@interface LXNotePopUpViewController : UIViewController
@property (copy, nonatomic) LXNotePopUpSaveHandler saveHandler;
@property (weak, nonatomic) id<ModalViewControllerDelegate> delegate;
@property (copy, nonatomic) NSString *noteText;

+ (instancetype)notePopUpViewController;

@end
