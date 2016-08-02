//
//  LXNotePopUpViewController.m
//  EvePopViewController
//
//  Created by Harry Duan on 8/1/16.
//  Copyright © 2016 Harry_Duan. All rights reserved.
//

#import "LXNotePopUpViewController.h"
#import "LXPresentAnimation.h"
#import "LXDismissAnimation.h"


@interface LXNotePopUpViewController ()<UITextViewDelegate, UIViewControllerTransitioningDelegate>

@property (weak, nonatomic) IBOutlet UITextView *noteTextView;
@property (weak, nonatomic) IBOutlet UILabel *wordCountLabel;
@property (weak, nonatomic) IBOutlet UIView *notePopUpView;
@property (weak, nonatomic) IBOutlet UIButton *saveButton;

@property (strong, nonatomic) LXPresentAnimation* presentAnimation;
@property (strong, nonatomic) LXDismissAnimation* dismissAnimation;
@property (copy, nonatomic) NSString *wordCount;
@property (assign) BOOL isValied;


@end

@implementation LXNotePopUpViewController


+ (instancetype)notePopUpViewController {
    return [[LXNotePopUpViewController alloc] init];
}

#pragma mark - Override
- (instancetype)init {
    if (self) {
        UIStoryboard* main = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
        self = [main instantiateViewControllerWithIdentifier:@"LXNotePopUpViewController"];
        
        self.presentAnimation = [LXPresentAnimation new];
        self.dismissAnimation = [LXDismissAnimation new];
        self.noteText = @"Hello World";
        
        self.modalPresentationStyle = UIModalPresentationCustom;
        self.transitioningDelegate = self;
        self.isValied = YES;
    }
    return self;
}

#pragma mark - life cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.notePopUpView.layer.cornerRadius = 10;
    self.notePopUpView.layer.masksToBounds = YES;
    self.noteTextView.delegate = self;
    self.noteTextView.text = self.noteText;
    [self textViewDidChange:self.noteTextView];
}



- (IBAction)toSaveNote:(id)sender {
    if (self.saveHandler) {
        self.saveHandler(self.noteTextView.text, self.noteText.length, self);
    }
    [self toDismissPopUpView:nil];
}

- (IBAction)toDismissPopUpView:(id)sender {
    if (self.delegate && [self.delegate respondsToSelector:@selector(modalViewControllerDidClickDismissButton:)]) {
        [self.delegate modalViewControllerDidClickDismissButton:self];
    }
}

- (void)textViewDidChange:(UITextView *)textView {
    self.noteText = textView.text;
    self.wordCount = [NSString stringWithFormat:@"%ld", (unsigned long)self.noteText.length];
    self.wordCountLabel.text = self.wordCount;
    
    if (self.noteText.length > 140 && self.isValied) {
        [UIView animateWithDuration:0.2
                         animations:^{
                             self.saveButton.alpha = 0.4;
                             self.wordCountLabel.textColor = [UIColor redColor];
                         }
                         completion:^(BOOL finished) {
                             self.saveButton.userInteractionEnabled = NO;
                             self.isValied = NO;
                         }];
    }
    if (self.noteText.length <= 140 && !self.isValied) {
        [UIView animateWithDuration:0.2
                         animations:^{
                             self.saveButton.alpha = 1;
                             self.wordCountLabel.textColor = [UIColor colorWithRed:165 / 255.f green:165 / 255.f blue:165 / 255.f alpha:1];
                         }
                         completion:^(BOOL finished) {
                             self.saveButton.userInteractionEnabled = YES;
                             self.isValied = YES;
                         }];
    }
}

#pragma mark - UIViewControllerTransitioningDelegate
- (id <UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source {
    return self.presentAnimation;
}

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    return self.dismissAnimation;
}

@end
