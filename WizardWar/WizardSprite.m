//
//  WizardSprite.m
//  WizardWar
//
//  Created by Sean Hess on 5/17/13.
//  Copyright (c) 2013 The LAB. All rights reserved.
//

#import "WizardSprite.h"
#import "cocos2d.h"
#import "CCLabelTTF.h"
#import <ReactiveCocoa.h>
#import "PEInvisible.h"
#import "PEHelmet.h"
#import "PEHeal.h"
#import "PESleep.h"
#import "AppStyle.h"
#import "PEUndies.h"
#import "DebugSprite.h"
#import "OLSprite.h"
#import "PECthulhu.h"
#import "PELevitate.h"
#import "ChatBubbleSprite.h"

#define SLEEP_ANIMATION_START_DELAY 0.2
#define WIZARD_PADDING 20
#define PIXELS_HIGH_PER_ALTITUDE 100


@interface WizardEffectOffset : NSObject
@property (nonatomic) float x;
@property (nonatomic) float y;
@property (nonatomic) float rotation;
@property (nonatomic, readonly) CGPoint point;
@end

@implementation WizardEffectOffset
-(CGPoint)point {
    return ccp(self.x, self.y);
}
@end


@interface WizardSprite () <OLSpriteFrameDelegate>
@property (nonatomic, strong) Units * units;

@property (nonatomic, readonly) BOOL isSingleFrame;
@property (nonatomic, strong) CCLabelTTF * label;
@property (nonatomic, strong) ChatBubbleSprite * chatBubble;
@property (nonatomic, strong) CCSprite * single;
@property (nonatomic, strong) OLSprite * skin;
@property (nonatomic, strong) CCSprite * clothes;
@property (nonatomic, strong) CCSprite * effect;

@property (nonatomic, strong) CCAction * hoverAction;

@property (nonatomic, strong) Match * match;
@property (nonatomic) BOOL isCurrentWizard;



@property (nonatomic, strong) WizardEffectOffset* browOffset;
@property (nonatomic) CGPoint waistCenter;

@property (nonatomic, strong) CCSprite * headDebug;

@property (nonatomic, strong) CCActionInterval * skinStatusAction;
@property (nonatomic, strong) CCActionInterval * clothesStatusAction;
@property (nonatomic, strong) CCAnimation * skinStatusAnimation;
@property (nonatomic, strong) CCAnimation * clothesStatusAnimation;
@property (nonatomic) NSInteger currentStatusFrame;
@property (nonatomic) NSTimeInterval currentTime;

@property (nonatomic, strong) CCAction * skinEffectAction;
@property (nonatomic, strong) CCAction * clothesEffectAction;


@property (nonatomic, strong) NSMapTable * wizard1HeadOffsets;

@property (nonatomic) CCSpriteFrame * currentSkinFrame;

@property (nonatomic, strong) PlayerEffect * currentEffect;

@property (nonatomic, strong) NSString * chatMessage;
@property (nonatomic) MatchStatus matchStatus;
@property (nonatomic) WizardStatus wizardStatus;

@end

@implementation WizardSprite

-(id)initWithWizard:(Wizard *)wizard units:(Units *)units match:(Match*)match isCurrentWizard:(BOOL)isCurrentWizard hideControls:(RACSignal *)hideControls {
    if ((self=[super init])) {
        
        self.wizard = wizard;
        self.units = units;
        self.match = match;
        self.isCurrentWizard = isCurrentWizard;
        self.scale = units.spriteScaleModifier;
        
        __weak WizardSprite * wself = self;
        
        // I need to only show this if the game hasn't started!
        self.label = [CCLabelTTF labelWithString:self.wizardName fontName:FONT_COMIC_ZINE fontSize:36];
        self.label.position = ccp(self.wizard.direction*10, 100);
        self.label.horizontalAlignment = NSTextAlignmentCenter;
        self.label.verticalAlignment = kCCVerticalTextAlignmentBottom;
        self.label.dimensions = CGSizeMake(200, 400);
        self.label.anchorPoint = ccp(0.5, 0);
        [self addChild:self.label];        
        
        self.chatBubble = [ChatBubbleSprite new];
        [self addChild:self.chatBubble];
        self.chatBubble.scale = 0;
        self.chatBubble.position = self.chatBubblePosition;
        
        if (self.isSingleFrame) {
            self.single = [CCSprite spriteWithSpriteFrameName:[NSString stringWithFormat:@"%@.png", self.wizard.wizardType]];
            [self addChild:self.single];
        }
        
        else {
            self.skin = [OLSprite node];
            self.skin.delegate = self;
            self.clothes = [CCSprite node];
            ccColor3B color = [self colorWithColor:wizard.color];
            self.clothes.color = color;
            [self addChild:self.skin];
            [self addChild:self.clothes];
        }
        
        
#if TARGET_IPHONE_SIMULATOR && DEBUG
        self.headDebug = [DebugSprite new];
        [self addChild:self.headDebug];
#endif
        
        // BIND: state, position
        
        [[RACAble(self.wizard.position) distinctUntilChanged] subscribeNext:^(id x) {
            [wself renderPosition];
        }];
        
        
        [[RACAble(self.wizard.effect) distinctUntilChanged] subscribeNext:^(id x) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [wself renderEffect];
            });
        }];
        
        [[RACAble(self.wizard.altitude) distinctUntilChanged] subscribeNext:^(id x) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [wself renderAltitude];
            });
        }];
        
        RACSignal * matchStatusSignal = [RACAble(self.match.status) distinctUntilChanged];
        RAC(self.wizardStatus) = [RACAble(self.wizard.state) distinctUntilChanged];
        RAC(self.matchStatus) = matchStatusSignal;

        RAC(self.chatMessage) = RACAble(self.wizard.message);
        
        RAC(self.label.visible) = [[hideControls combineLatestWith:matchStatusSignal] reduceEach:^(NSNumber*hideControls, NSNumber*status) {
            return @(!hideControls.intValue && (status.intValue == MatchStatusReady || status.intValue == MatchStatusSyncing));
        }];
        
        self.wizard = wizard;
        
    }
    return self;
}


-(CGPoint)chatBubblePosition {
    return ccp(self.wizard.direction * 52, 120);
}

-(BOOL)isSingleFrame {
    return [self.wizard.wizardType isEqualToString:WIZARD_TYPE_DUMMY];
}

-(NSMapTable*)wizard1HeadOffsets {
    if (!_wizard1HeadOffsets) {
        NSMapTable * mapTable = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsObjectPersonality];
        
        [self mapTable:mapTable setOffset:ccp(0,0) rotation:0 forAnimationName:@"wizard1-prepare.png"];
        [self mapTable:mapTable setOffset:ccp(-3,-4) rotation:0 forAnimationName:@"wizard1-prepare2.png"];
        [self mapTable:mapTable setOffset:ccp(-5,-5) rotation:-1 forAnimationName:@"wizard1-prepare3.png"];
        [self mapTable:mapTable setOffset:ccp(-9,-9) rotation:-2 forAnimationName:@"wizard1-prepare4.png"];

        [self mapTable:mapTable setOffset:ccp(-5,5) rotation:0 forAnimationName:@"wizard1-attack2.png"];
        [self mapTable:mapTable setOffset:ccp(0,2) rotation:0 forAnimationName:@"wizard1-attack3.png"];
        [self mapTable:mapTable setOffset:ccp(8,-3) rotation:0 forAnimationName:@"wizard1-attack4.png"];
        [self mapTable:mapTable setOffset:ccp(8,-3) rotation:0 forAnimationName:@"wizard1-attack.png"];
        
//        [self mapTable:mapTable setOffset:ccp(0,0) rotation:0 forAnimationName:@"wizard1-damage.png"];
        [self mapTable:mapTable setOffset:ccp(-7,-3) rotation:0 forAnimationName:@"wizard1-damage2.png"];
        [self mapTable:mapTable setOffset:ccp(-17,-3) rotation:0 forAnimationName:@"wizard1-damage3.png"];
        [self mapTable:mapTable setOffset:ccp(-19,7) rotation:0 forAnimationName:@"wizard1-damage4.png"];
        [self mapTable:mapTable setOffset:ccp(-36,1) rotation:-10 forAnimationName:@"wizard1-damage5.png"];
        [self mapTable:mapTable setOffset:ccp(-49,-10) rotation:-20 forAnimationName:@"wizard1-damage6.png"];
        self.wizard1HeadOffsets = mapTable;
    }
    
    return _wizard1HeadOffsets;
}

-(void)mapTable:(NSMapTable*)mapTable setOffset:(CGPoint)point rotation:(float)rotation forAnimationName:(NSString*)name {
    WizardEffectOffset * offset = [WizardEffectOffset new];
    offset.x = point.x;
    offset.y = point.y;
    offset.rotation = rotation;
    [mapTable setObject:offset forKey:[[CCSpriteFrameCache sharedSpriteFrameCache] spriteFrameByName:name]];
}
     
     
-(ccColor3B)colorWithColor:(UIColor*)color {
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha =0.0;
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    return ccc3((int)(red * 255), (int)(green * 255), (int)(blue * 255));
}

-(CGPoint)calculatedPosition {
    return ccp([self.units toX:self.wizard.position], [self.units altitudeY:self.wizard.altitude]);
}

-(void)renderPosition {
    self.position = self.calculatedPosition;
//    NSLog(@"renderPosition %@", NSStringFromCGPoint(self.position));
    BOOL flip = (self.wizard.direction < 0);
    self.skin.flipX = flip;
    self.clothes.flipX = flip;
    self.chatBubble.flipX = flip;
    self.single.flipX = flip;
}

-(void)update:(ccTime)delta {}

-(void)sprite:(OLSprite *)sprite didChangeFrame:(CCSpriteFrame *)frame {
    [self alignBrow:frame];
}

-(void)alignBrow:(CCSpriteFrame*)currentFrame {
    
    if (self.wizard.state == WizardStatusDead || self.wizard.state == WizardStatusWon || [self.wizard.effect isKindOfClass:[PESleep class]])
        return;

    if (!currentFrame) {
        NSLog(@"CANT FIND FRAME status=%i", self.wizard.state);
        return;
    }
    
    CGPoint restBrow = ccp(0, 70);
    WizardEffectOffset* headOffset = [self.wizard1HeadOffsets objectForKey:currentFrame];
    
    if (!headOffset) {
        NSLog(@"CANT FIND FRAME OFFSET status=%i currentFrame=%@", self.wizard.state, currentFrame);
        return;
    }
    
    WizardEffectOffset* browOffset = [WizardEffectOffset new];
    browOffset.x = self.wizard.direction*headOffset.x;
    browOffset.y = restBrow.y + headOffset.y;
    browOffset.rotation = headOffset.rotation;
    self.browOffset = browOffset;
    self.headDebug.position = browOffset.point;
    
    if ([self.wizard.effect isKindOfClass:[PEHelmet class]]) {
        [self alignHelmet];
    }
}

-(void)alignHelmet {
    CGPoint helmetOffset = ccp(self.wizard.direction*-4, 22);
    self.effect.position = ccp(self.browOffset.x+helmetOffset.x, self.browOffset.y+helmetOffset.y);
    self.effect.rotation = self.wizard.direction*self.browOffset.rotation;
}

-(void)setChatMessage:(NSString*)message {
    if (message) {
        // start at 0, animate out
        self.chatBubble.scale = 0;
        CCAction * popIn = [CCScaleTo actionWithDuration:0.2 scale:1.0];
        [self.chatBubble runAction:popIn];
    }
    else {
        CCAction * popOut = [CCScaleTo actionWithDuration:0.2 scale:0.0];
        [self.chatBubble runAction:popOut];
    }
    self.chatBubble.message = message;
    _chatMessage = message;
}

-(void)setWizardStatus:(WizardStatus)status {
    
    if (self.wizard.effect.class == PESleep.class && (status == WizardStatusReady || status == WizardStatusHit || status == WizardStatusCast))
        return;
    
    if (self.isSingleFrame) {
        if (self.wizard.state == WizardStatusDead) {
            [self.single runAction:[CCFadeOut actionWithDuration:0.4]];
        }
        
        else if (self.wizard.state == WizardStatusHit) {
            CCMoveBy * up = [CCMoveBy actionWithDuration:0.1 position:ccp(0, 10)];
            CCMoveBy * down = [CCMoveBy actionWithDuration:0.1 position:ccp(0, -10)];
            CCSequence * sequence = [CCSequence actions:up, down, nil];
            [self.single runAction:sequence];
        }
        
        return;
    }
    
    [self.skin stopAction:self.skinStatusAction];
    [self.clothes stopAction:self.clothesStatusAction];
    
    CCAnimation * skinAnimation = [self animationForStatus:status clothes:NO];
    CCAnimation * clothesAnimation = [self animationForStatus:status clothes:YES];
    
    self.skinStatusAnimation = skinAnimation;
    self.clothesStatusAnimation = clothesAnimation;
    self.currentStatusFrame = 0;

    self.skinStatusAction = [CCAnimate actionWithAnimation:skinAnimation];
    [self.skin runAction:self.skinStatusAction];

    self.clothesStatusAction = [CCAnimate actionWithAnimation:clothesAnimation];
    [self.clothes runAction:self.clothesStatusAction];
    
//    if ([self.wizard.effect isKindOfClass:[EffectHelmet class]]) {
//        // I need to stop this at the same time :(
//    }
}

// The problem is that the clothes, skin, and whatever are NOT independent of each other.
// So I should play through them perhaps?
// I could index them depending on the delta...
-(CCAnimation*)animationForStatus:(WizardStatus)status clothes:(BOOL)isClothes {
    if (self.isSingleFrame) return nil;
    NSString * clothesSuffix = (isClothes) ? @"-clothes" : @"";
    NSString * animationName = [NSString stringWithFormat:@"%@%@", [self animationNameForStatus:status], clothesSuffix];
    CCAnimation *animation = [[CCAnimationCache sharedAnimationCache] animationByName:animationName];
    
    if (self.wizard.state == WizardStatusReady || self.wizard.state == WizardStatusWon)
        animation.loops = 1000;

    NSAssert(animation, @"DID NOT LOAD ANIMATION");
    return animation;
}

- (void)setMatchStatus:(MatchStatus)status {
    if ((status == MatchStatusReady || status == MatchStatusSyncing) && self.isCurrentWizard) {
        CCTintTo * glow = [CCTintTo actionWithDuration:0.2 red:0 green:255 blue:0];
        CCTintTo * normal = [CCTintTo actionWithDuration:0.2 red:255 green:255 blue:255];
        CCSequence * sequence = [CCSequence actions:glow, normal, glow, normal, glow, normal, nil];
        [self.skin runAction:sequence];
    }
    else {
        self.skin.color = ccWHITE;
    }
}

- (NSString*)wizardName {
    if (self.isCurrentWizard) return @"You";
    else return self.wizard.name;
}

- (void)renderEffect {
    
    if (self.effect) {
        [self removeChild:self.effect];
        self.effect = nil;
    }
    
//    NSLog(@"RENDER EFFECT %@ = %@", self.wizard.name, self.wizard.effect);
    
    [self.skin stopAction:self.skinEffectAction];
    [self.clothes stopAction:self.clothesEffectAction];
    self.skinEffectAction = nil;
    self.clothesEffectAction = nil;
    
    self.skin.opacity = 255;
    self.clothes.opacity = 255;
    
    // set opactiy based on invisible
    if ([self.wizard.effect class] == [PEInvisible class]) {
        self.skinEffectAction = [CCFadeTo actionWithDuration:self.wizard.effect.delay opacity:20];
        self.clothesEffectAction = [CCFadeTo actionWithDuration:self.wizard.effect.delay opacity:20];
        
        [self.skin runAction:self.skinEffectAction];
        [self.clothes runAction:self.clothesEffectAction];        
    }
    
    else if ([self.wizard.effect class] == [PEHelmet class]) {
        [self setWizardStatus:self.wizard.state];
        self.effect = [CCSprite spriteWithSpriteFrameName:@"helmet.png"];
        self.effect.flipX = self.wizard.position == UNITS_MAX;
        [self alignHelmet];
        
        // well, I just finished my cast animation I guess
        // I need to pin it to the wizard's center
        // I need to know which frame of the wizard animation I am on.
        // then set it every update
        
        // I KNOW I just cast a spell, so I'm in the middle of the cast animation
//        [self moveHelmetAround:self.wizard.state];
    }
    
    else if ([self.wizard.effect class] == [PEHeal class]) {
//        self.skin.color = ccc3(255, 255, 255);
//        [self.skin setBlendFunc: (ccBlendFunc) { GL_ONE, GL_ONE }];
//        [self.skin runAction: [CCRepeatForever actionWithAction:[CCSequence actions:[CCScaleTo actionWithDuration:0.9f scaleX:size.width scaleY:size.height], [CCScaleTo actionWithDuration:0.9f scaleX:size.width*0.75f scaleY:size. height*0.75f], nil] ]];
        
//        [self.skin runAction: [CCRepeatForever actionWithAction:[CCSequence actions:[CCFadeTo actionWithDuration:0.9f opacity:150], [CCFadeTo actionWithDuration:0.9f opacity:255], nil]]];
        CCFiniteTimeAction * toRed = [CCTintTo actionWithDuration:1 red:255 green:100 blue:100];
        CCFiniteTimeAction * toNormal = [CCTintTo actionWithDuration:1 red:255 green:255 blue:255];
        CCAction * glowRed = [CCRepeatForever actionWithAction:[CCSequence actions:toRed, toNormal, nil]];
        self.skinEffectAction = glowRed;
        
        [self.skin runAction:self.skinEffectAction];
    }
    
    else if ([self.wizard.effect class] == [PESleep class]) {
        self.skinEffectAction = [self actionForSleepEffectForClothes:NO];
        self.clothesEffectAction = [self actionForSleepEffectForClothes:YES];
        
        // then when the effect wears off, we need to re-render status
        if (![self.currentEffect isKindOfClass:[PESleep class]] && !self.isSingleFrame) {
            float start = -90;
            self.rotation = start;
            CCFiniteTimeAction * rotate = [CCRotateTo actionWithDuration:SLEEP_ANIMATION_START_DELAY angle:start+90];
            [self runAction:rotate];
        }
        
        // you get 2 actions conflicting here!
        // TODO fix getting hit by sleep

        [self.skin stopAction:self.skinEffectAction];
        [self.skin stopAction:self.skinStatusAction];
        [self.skin runAction:self.skinEffectAction];
        [self.clothes stopAction:self.clothesEffectAction];
        [self.clothes stopAction:self.clothesStatusAction];
        [self.clothes runAction:self.clothesEffectAction];
    }
    
    else if ([self.wizard.effect class] == [PEUndies class]) {
        self.effect = [CCSprite spriteWithSpriteFrameName:@"wizard-undies.png"];
//        self.effect.flipY = YES;
        self.effect.position = ccp(self.wizard.direction*-12, -30);
        
        
    }
    
    else if ([self.wizard.effect class] == [PECthulhu class]) {
//        self.effect = [CCSprite spriteWithSpriteFrameName:@"wizard-undies.png"];
    }
    
    else {
        self.skin.color = ccc3(255, 255, 255);
//        self.clothes.color = [self colorWithColor:self.wizard.color];
//        [self runAction:[CCMoveTo actionWithDuration:0.2 position:self.calculatedPosition]];
//        [self runAction:[CCRotateTo actionWithDuration:0.2 angle:0]];
        [self setWizardStatus:self.wizard.state];
    }
    
    if (self.effect)
        [self addChild:self.effect];
    
    self.currentEffect = self.wizard.effect;
    return;
}

//-(void)moveHelmetAround:(WizardStatus)status {
//    CCAction * action;
//    CGPoint rest = ccp(-6*self.wizard.direction, 90);
//    CGPoint castback = ccp(rest.x-6, rest.y+10);
////    self.effect.position = res    t;
//    
//    if (status == WizardStatusCast) {
//        self.effect.position = castback;
//        action = [CCMoveTo actionWithDuration:0.1 position:rest];
//    } else if (status == WizardStatusReady) {
//        
//    } else if (status == WizardStatusHit) {
//        
//    }
//    
//    [self.effect runAction:action];
//}

-(CCAction*)actionForSleepEffectForClothes:(BOOL)isClothes {
    // I have to set the angle to 0 degrees right when the animation starts
    // crap. 
    
    NSString * clothesSuffix = (isClothes) ? @"-clothes" : @"";
    NSString * animationName = [NSString stringWithFormat:@"wizard1-sleep%@", clothesSuffix];
//    CCFiniteTimeAction * wait = [CCFadeTo actionWithDuration:SLEEP_ANIMATION_START_DELAY opacity:255];
    CCAnimation *sleep = [[CCAnimationCache sharedAnimationCache] animationByName:animationName];
    NSAssert(sleep, @"DID NOT LOAD ANIMATION");
    sleep.loops = 1000;
//    CCSequence * sequence = [CCSequence actions:wait, [CCAnimate actionWithAnimation:sleep], nil];
    return [CCAnimate actionWithAnimation:sleep];
}

-(void)renderAltitude {
    CGPoint pos = self.calculatedPosition;
//    NSLog(@"renderAltitude %@ %f %@", self.wizard.name, self.wizard.altitude, NSStringFromCGPoint(self.position));
    CGFloat dy = [self.units toHeight:self.wizard.altitude];
    CCFiniteTimeAction * toPos = [CCMoveTo actionWithDuration:0.2 position:ccp(pos.x, pos.y)];
    if (self.wizard.altitude == 1.0 && [self.wizard.effect isKindOfClass:[PELevitate class]]) {
        CCFiniteTimeAction * toHover = [CCMoveTo actionWithDuration:0.2 position:ccp(pos.x, pos.y+5)];
        self.hoverAction = [CCRepeatForever actionWithAction:[CCSequence actions:toPos, toHover, nil]];
        [self runAction:self.hoverAction];

        CCFiniteTimeAction * toChatBubblePos = [CCMoveTo actionWithDuration:0.2 position:ccp(self.chatBubblePosition.x+30*self.wizard.direction, self.chatBubblePosition.y-dy)];
        [self.chatBubble runAction:toChatBubblePos];
    }
    else if (self.wizard.altitude == 0.0) {
        [self stopAction:self.hoverAction];
        [self runAction:toPos];

        CCFiniteTimeAction * toChatBubblePos = [CCMoveTo actionWithDuration:0.2 position:self.chatBubblePosition];
        [self.chatBubble runAction:toChatBubblePos];
    } else {
        self.position = pos;
        self.chatBubble.position = self.chatBubblePosition;
    }
}


-(NSString*)animationNameForStatus:(WizardStatus)status {
    if (self.isSingleFrame) return nil;
    NSString * stateName = @"prepare";
    
    if (self.wizard.state == WizardStatusCast)
        stateName = @"attack";
    
    else if(self.wizard.state == WizardStatusHit)
        stateName = @"damage";
    
    else if(self.wizard.state == WizardStatusDead)
        stateName = @"dead";
    
    else if(self.wizard.state == WizardStatusWon)
        stateName = @"celebrate";
    
    return [NSString stringWithFormat:@"%@-%@", self.wizardSheetName, stateName];
}

-(NSString*)wizardSheetName {
    return [NSString stringWithFormat:@"wizard%@", self.wizard.wizardType];
}

@end
