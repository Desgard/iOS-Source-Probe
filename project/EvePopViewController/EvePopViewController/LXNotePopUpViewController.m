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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    
    self.notePopUpView.layer.cornerRadius = 10;
    self.notePopUpView.layer.masksToBounds = YES;
    self.noteTextView.delegate = self;
    self.noteTextView.text = self.noteText;
    
    [self textViewDidChange:self.noteTextView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.noteTextView becomeFirstResponder];
}

- (IBAction)toSaveNote:(id)sender {
    if (self.saveHandler) {
        self.saveHandler(self, self.noteTextView.text);
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

#pragma mark - Notification Handlers
- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    
    double duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    CGRect keyboardF = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    
    CGFloat dis = self.view.frame.origin.y + self.view.frame.size.height - keyboardF.origin.y;
    if (dis > -10) {
        CGFloat animationDis = dis + 10;
        
        NSLog(@"%lf", animationDis);
        [UIView animateWithDuration:duration animations:^{
            self.view.center = CGPointMake(self.view.center.x, self.view.center.y - animationDis);
        } completion:nil];
    }
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    double duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
//        self.view.transform = CGAffineTransformIdentity;
        self.view.center = CGPointMake([UIScreen mainScreen].bounds.size.width / 2, [UIScreen mainScreen].bounds.size.height / 2);
    } completion:nil];
}



@end
