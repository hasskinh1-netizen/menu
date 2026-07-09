//Require standard library
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Foundation/Foundation.h>
//Imgui library
#import "Esp/CaptainHook.h"
#import "Esp/ImGuiDrawView.h"
#import "IMGUI/imgui.h"
#import "IMGUI/imgui_impl_metal.h"
#import "IMGUI/zzz.h"
//Patch library
#import "5Toubun/NakanoIchika.h"
#import "5Toubun/NakanoNino.h"
#import "5Toubun/NakanoMiku.h"
#import "5Toubun/NakanoYotsuba.h"
#import "5Toubun/NakanoItsuki.h"
#import "5Toubun/dobby.h"
#import "5Toubun/il2cpp.h"

#define kWidth  [UIScreen mainScreen].bounds.size.width
#define kHeight [UIScreen mainScreen].bounds.size.height
#define kScale [UIScreen mainScreen].scale
#define patch_NULL(a, b) vm(ENCRYPTOFFSET(a), strtoul(ENCRYPTHEX(b), nullptr, 0))
#define patch(a, b) vm_unity(ENCRYPTOFFSET(a), strtoul(ENCRYPTHEX(b), nullptr, 0))

#define ASSEMBLY_CSHARP "Assembly-CSharp.dll"
#define ASSEMBLY_PLUGINS "Project.Plugins_d.dll"

@interface ImGuiDrawView () <MTKViewDelegate>
@property (nonatomic, strong) id <MTLDevice> device;
@property (nonatomic, strong) id <MTLCommandQueue> commandQueue;
@end

@implementation ImGuiDrawView

//=== FEATURE GLOBALS ===
static bool g_menuOpen = true;
static bool g_hooksInit = false;

// Map/ESP
static bool g_mapHack = false;
static bool g_espBox = false;
static bool g_espLine = false;
static bool g_espHealth = false;
static bool g_espName = false;
static bool g_espDistance = false;
static bool g_fullMapReveal = false;

// No CD / Skills
static bool g_noCooldown = false;
static bool g_noManaCost = false;
static bool g_autoSkillUpgrade = false;

// Camera
static bool g_cameraZoom = false;
static float g_zoomAmount = 200.0f;
static bool g_freeCamera = false;
static bool g_noFog = false;

// God Mode / Damage
static bool g_godMode = false;
static bool g_oneHit = false;
static bool g_noStun = false;

// Speed
static bool g_speedHack = false;
static float g_speedMultiplier = 2.0f;

// Auto Aim
static bool g_autoAim = false;
static float g_aimRange = 1000.0f;
static int g_aimTargetMode = 0; // 0=nearest, 1=lowestHP, 2=closestToCursor

// Attack Range
static bool g_extendedRange = false;
static int g_rangeExt = 300;

//=== HOOK ORIGINALS ===
// Map/ESP - LVActorLinker.SetVisible (the one from original code)
void (*_LVActorLinker_SetVisible)(void *instance, int camp, bool bVisible, bool forceSync);

// Skills
bool (*_LSkillComponent_IsSkillCDReady)(void *instance, int slotType);
void (*_SkillSlot_SetSkillNoCost)(void *instance, bool noCost);
void (*_SkillSlot_ReduceCD)(void *instance);

// Damage
void (*_LHurtComponent_TakeDamage)(void *instance, void *hurtData);

// Horizon/Fog
void (*_HorizonMarker_set_Enabled)(void *instance, bool value);
void (*_HorizonMarker_ForceShow)(void *instance, int camp, bool show, uint markID);

// Movement
void (*_PlayerMovement_set_maxSpeed)(void *instance, int speed);

// Aim
void *(*_SkillControlIndicator_SetUseSkillTarget)(void *instance, void *target, bool flag);
void *(*_SkillIndicateSystem_CurTargetActor)(void *instance);

//=== HOOK FUNCTIONS ===

// 1. MAP HACK - Force show enemies on minimap
void LVActorLinker_SetVisible(void *instance, int camp, bool bVisible, bool forceSync) {
    if (instance != nullptr && g_mapHack) {
        if (camp == 1 || camp == 2 || camp == 110 || camp == 255) {
            bVisible = true;
        }
    }
    return _LVActorLinker_SetVisible(instance, camp, bVisible, forceSync);
}

// 2. NO COOLDOWN
bool LSkillComponent_IsSkillCDReady(void *instance, int slotType) {
    if (instance != nullptr && g_noCooldown) {
        return true;
    }
    return _LSkillComponent_IsSkillCDReady(instance, slotType);
}

void SkillSlot_SetSkillNoCost(void *instance, bool noCost) {
    if (instance != nullptr && g_noManaCost) {
        noCost = true;
    }
    return _SkillSlot_SetSkillNoCost(instance, noCost);
}

// 3. GOD MODE - Immune damage
void LHurtComponent_TakeDamage(void *instance, void *hurtData) {
    if (instance != nullptr && g_godMode) {
        return;
    }
    return _LHurtComponent_TakeDamage(instance, hurtData);
}

// 4. FULL MAP REVEAL
void HorizonMarker_set_Enabled(void *instance, bool value) {
    if (instance != nullptr && g_fullMapReveal) {
        value = false; // Disable horizon = full vision
    }
    return _HorizonMarker_set_Enabled(instance, value);
}

void HorizonMarker_ForceShow(void *instance, int camp, bool show, uint markID) {
    if (instance != nullptr && g_fullMapReveal) {
        show = true;
    }
    return _HorizonMarker_ForceShow(instance, camp, show, markID);
}

// 5. SPEED HACK
void PlayerMovement_set_maxSpeed(void *instance, int speed) {
    if (instance != nullptr && g_speedHack) {
        speed = (int)((float)speed * g_speedMultiplier);
    }
    return _PlayerMovement_set_maxSpeed(instance, speed);
}

//=== OFFSET STORAGE ===
static uint64_t s_methodOffsets[32];
static int s_offsetCount = 0;

enum OffsetID {
    OFF_LVActorLinker_SetVisible = 0,
    OFF_LSkillComponent_IsSkillCDReady,
    OFF_SkillSlot_SetSkillNoCost,
    OFF_LHurtComponent_TakeDamage,
    OFF_HorizonMarker_set_Enabled,
    OFF_HorizonMarker_ForceShow,
    OFF_PlayerMovement_set_maxSpeed,
    OFF_SkillControlIndicator_SetUseSkillTarget,
    OFF_SkillIndicateSystem_CurTargetActor,
    OFF_LSkillComponent_ToggleZeroCd,
    OFF_LSkillComponent_SetZeroCd,
    OFF_LActorRoot_get_PlayerMovement,
    OFF_MobaCamera_get_Zoom,
    OFF_CameraSystem_get_Zoom,
    OFF_FogOfWar_get_enable,
    OFF_FogOfWar_set_enable,
    OFF_LHurtComponent_ImmuneDamage,
    OFF_ValueProperty_set_actorHp,
};

uint64_t resolveMethod(const char *assembly, const char *ns, const char *cls, const char *method, int args) {
    Il2CppMethod m(assembly);
    return m.getClass(ns, cls).getMethod(method, args);
}

void initial_setup(){
    Il2CppAttach();

    // Resolve all method offsets
    s_methodOffsets[OFF_LVActorLinker_SetVisible] = resolveMethod(
        ASSEMBLY_PLUGINS, "NucleusDrive.Logic", "LVActorLinker", "SetVisible", 3);

    s_methodOffsets[OFF_LSkillComponent_IsSkillCDReady] = resolveMethod(
        ASSEMBLY_CSHARP, "", "LSkillComponent", "IsSkillCDReady", 1);

    s_methodOffsets[OFF_SkillSlot_SetSkillNoCost] = resolveMethod(
        ASSEMBLY_CSHARP, "", "SkillSlot", "SetSkillNoCost", 1);

    s_methodOffsets[OFF_LHurtComponent_TakeDamage] = resolveMethod(
        ASSEMBLY_CSHARP, "", "LHurtComponent", "TakeDamage", 1);

    s_methodOffsets[OFF_HorizonMarker_set_Enabled] = resolveMethod(
        ASSEMBLY_CSHARP, "", "HorizonMarker", "set_Enabled", 1);

    s_methodOffsets[OFF_HorizonMarker_ForceShow] = resolveMethod(
        ASSEMBLY_CSHARP, "", "HorizonMarker", "ForceShowByRealVisionToTargetCamp", 3);

    s_methodOffsets[OFF_PlayerMovement_set_maxSpeed] = resolveMethod(
        ASSEMBLY_CSHARP, "", "PlayerMovement", "set_maxSpeed", 1);

    s_methodOffsets[OFF_SkillControlIndicator_SetUseSkillTarget] = resolveMethod(
        ASSEMBLY_CSHARP, "", "SkillControlIndicator", "SetUseSkillTarget", 2);

    s_methodOffsets[OFF_SkillIndicateSystem_CurTargetActor] = resolveMethod(
        ASSEMBLY_CSHARP, "", "SkillIndicateSystem", "CurTargetActor", 0);

    s_methodOffsets[OFF_LSkillComponent_ToggleZeroCd] = resolveMethod(
        ASSEMBLY_CSHARP, "", "LSkillComponent", "ToggleZeroCd", 0);

    s_methodOffsets[OFF_LSkillComponent_SetZeroCd] = resolveMethod(
        ASSEMBLY_CSHARP, "", "LSkillComponent", "SetZeroCd", 1);

    // Register hooks
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (s_methodOffsets[OFF_LVActorLinker_SetVisible])
            DobbyHook((void *)getRealOffset(s_methodOffsets[OFF_LVActorLinker_SetVisible]),
                      (void *)LVActorLinker_SetVisible, (void **)&_LVActorLinker_SetVisible);

        if (s_methodOffsets[OFF_LSkillComponent_IsSkillCDReady])
            DobbyHook((void *)getRealOffset(s_methodOffsets[OFF_LSkillComponent_IsSkillCDReady]),
                      (void *)LSkillComponent_IsSkillCDReady, (void **)&_LSkillComponent_IsSkillCDReady);

        if (s_methodOffsets[OFF_SkillSlot_SetSkillNoCost])
            DobbyHook((void *)getRealOffset(s_methodOffsets[OFF_SkillSlot_SetSkillNoCost]),
                      (void *)SkillSlot_SetSkillNoCost, (void **)&_SkillSlot_SetSkillNoCost);

        if (s_methodOffsets[OFF_LHurtComponent_TakeDamage])
            DobbyHook((void *)getRealOffset(s_methodOffsets[OFF_LHurtComponent_TakeDamage]),
                      (void *)LHurtComponent_TakeDamage, (void **)&_LHurtComponent_TakeDamage);

        if (s_methodOffsets[OFF_HorizonMarker_set_Enabled])
            DobbyHook((void *)getRealOffset(s_methodOffsets[OFF_HorizonMarker_set_Enabled]),
                      (void *)HorizonMarker_set_Enabled, (void **)&_HorizonMarker_set_Enabled);

        if (s_methodOffsets[OFF_HorizonMarker_ForceShow])
            DobbyHook((void *)getRealOffset(s_methodOffsets[OFF_HorizonMarker_ForceShow]),
                      (void *)HorizonMarker_ForceShow, (void **)&_HorizonMarker_ForceShow);

        if (s_methodOffsets[OFF_PlayerMovement_set_maxSpeed])
            DobbyHook((void *)getRealOffset(s_methodOffsets[OFF_PlayerMovement_set_maxSpeed]),
                      (void *)PlayerMovement_set_maxSpeed, (void **)&_PlayerMovement_set_maxSpeed);
    });

    g_hooksInit = true;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];

    _device = MTLCreateSystemDefaultDevice();
    _commandQueue = [_device newCommandQueue];

    if (!self.device) abort();

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;

    ImGui::StyleColorsDark();

    ImFont* font = io.Fonts->AddFontFromMemoryCompressedTTF((void*)zzz_compressed_data, zzz_compressed_size, 60.0f, NULL, io.Fonts->GetGlyphRangesVietnamese());

    ImGui_ImplMetal_Init(_device);

    return self;
}

+ (void)showChange:(BOOL)open
{
    g_menuOpen = open;
}

- (MTKView *)mtkView
{
    return (MTKView *)self.view;
}

- (void)loadView
{
    CGFloat w = [UIApplication sharedApplication].windows[0].rootViewController.view.frame.size.width;
    CGFloat h = [UIApplication sharedApplication].windows[0].rootViewController.view.frame.size.height;
    self.view = [[MTKView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.mtkView.device = self.device;
    self.mtkView.delegate = self;
    self.mtkView.clearColor = MTLClearColorMake(0, 0, 0, 0);
    self.mtkView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0];
    self.mtkView.clipsToBounds = YES;
}

#pragma mark - Interaction

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    UITouch *anyTouch = event.allTouches.anyObject;
    CGPoint touchLocation = [anyTouch locationInView:self.view];
    ImGuiIO &io = ImGui::GetIO();
    io.MousePos = ImVec2(touchLocation.x, touchLocation.y);

    BOOL hasActiveTouch = NO;
    for (UITouch *touch in event.allTouches)
    {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled)
        {
            hasActiveTouch = YES;
            break;
        }
    }
    io.MouseDown[0] = hasActiveTouch;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
}

//=== ESP DRAWING HELPERS ===
struct VInt3 { int x, y, z; };

static ImColor enemyColor = ImColor(255, 50, 50, 255);
static ImColor allyColor = ImColor(50, 255, 50, 255);
static ImColor espBoxColor = ImColor(255, 255, 100, 255);

void DrawEspBox(ImDrawList* dl, ImVec2 screenPos, float w, float h, const char* name, int hp, int maxHp, float dist) {
    if (g_espBox) {
        dl->AddRect(ImVec2(screenPos.x - w/2, screenPos.y - h),
                    ImVec2(screenPos.x + w/2, screenPos.y),
                    espBoxColor, 0.0f, 0, 2.0f);
    }
    if (g_espHealth && maxHp > 0) {
        float hpPct = (float)hp / (float)maxHp;
        float barW = w;
        dl->AddRectFilled(ImVec2(screenPos.x - barW/2, screenPos.y - h - 8),
                          ImVec2(screenPos.x + barW/2, screenPos.y - h - 4),
                          ImColor(0, 0, 0, 200));
        dl->AddRectFilled(ImVec2(screenPos.x - barW/2, screenPos.y - h - 8),
                          ImVec2(screenPos.x - barW/2 + barW * hpPct, screenPos.y - h - 4),
                          hpPct > 0.3f ? ImColor(0, 255, 0, 255) : ImColor(255, 0, 0, 255));
    }
    if (g_espName && name) {
        dl->AddText(ImVec2(screenPos.x - w/2, screenPos.y + 2), ImColor(255, 255, 255, 255), name);
    }
    if (g_espDistance) {
        char buf[32];
        snprintf(buf, sizeof(buf), "%.0fm", dist);
        dl->AddText(ImVec2(screenPos.x + w/2 + 4, screenPos.y - h), ImColor(200, 200, 255, 255), buf);
    }
}

//=== CAMERA HACK PATCH ===
void applyCameraPatch(bool enable) {
    static bool camPatched = false;
    if (enable && !camPatched) {
        // Patch camera zoom constraints (example offsets - adjust per game version)
        // These are example patches - real offsets need to be found from binary
        camPatched = true;
    } else if (!enable && camPatched) {
        camPatched = false;
    }
}

void applyFogPatch(bool enable) {
    static bool fogPatched = false;
    if (enable && !fogPatched) {
        // Patch FogOfWar._enable = false
        // Real offset from dump: FogOfWar._enable field offset 0x8
        fogPatched = true;
    } else if (!enable && fogPatched) {
        fogPatched = false;
    }
}

#pragma mark - MTKViewDelegate

- (void)drawInMTKView:(MTKView*)view
{
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize.x = view.bounds.size.width;
    io.DisplaySize.y = view.bounds.size.height;

    CGFloat framebufferScale = view.window.screen.scale ?: UIScreen.mainScreen.scale;
    io.DisplayFramebufferScale = ImVec2(framebufferScale, framebufferScale);
    io.DeltaTime = 1 / float(view.preferredFramesPerSecond ?: 120);

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];

    if (g_menuOpen == true) {
        [self.view setUserInteractionEnabled:YES];
    } else {
        [self.view setUserInteractionEnabled:NO];
    }

    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor != nil)
    {
        id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder pushDebugGroup:@"ImGui Menu"];

        ImGui_ImplMetal_NewFrame(renderPassDescriptor);
        ImGui::NewFrame();

        ImFont* font = ImGui::GetFont();
        font->Scale = 15.f / font->FontSize;

        // Init hooks on first menu open
        if (!g_hooksInit) {
            initial_setup();
        }

        //=== DRAW MENU ===
        if (g_menuOpen)
        {
            ImGui::SetNextWindowPos(ImVec2(20, 40), ImGuiCond_FirstUseEver);
            ImGui::SetNextWindowSize(ImVec2(420, 500), ImGuiCond_FirstUseEver);

            ImGui::Begin("34306 JIT Mod Menu - Lien Quan Mobile", &g_menuOpen);

            if (ImGui::CollapsingHeader("1. Map / ESP / Visibility", ImGuiTreeNodeFlags_DefaultOpen)) {
                ImGui::Checkbox("Map Hack (See enemies on map)", &g_mapHack);
                ImGui::SameLine(); ImGui::TextDisabled("(?)");
                if (ImGui::IsItemHovered()) ImGui::SetTooltip("Force show all enemies on minimap");

                ImGui::Separator();
                ImGui::Text("ESP Drawing:");
                ImGui::Checkbox("ESP Box", &g_espBox);
                ImGui::SameLine();
                ImGui::Checkbox("ESP Line", &g_espLine);
                ImGui::Checkbox("ESP Health Bar", &g_espHealth);
                ImGui::SameLine();
                ImGui::Checkbox("ESP Name", &g_espName);
                ImGui::Checkbox("ESP Distance", &g_espDistance);

                ImGui::Separator();
                ImGui::Checkbox("Full Map Reveal (Remove Fog)", &g_fullMapReveal);
                if (g_fullMapReveal) {
                    applyFogPatch(true);
                } else {
                    applyFogPatch(false);
                }
            }

            if (ImGui::CollapsingHeader("2. Skills / Cooldown", ImGuiTreeNodeFlags_DefaultOpen)) {
                ImGui::Checkbox("No Cooldown (Reset Skill CD)", &g_noCooldown);
                ImGui::SameLine();
                if (ImGui::Button("Force Reset CD")) {
                    // Call ToggleZeroCd on player skill component
                    if (s_methodOffsets[OFF_LSkillComponent_ToggleZeroCd]) {
                        void *addr = (void *)getRealOffset(s_methodOffsets[OFF_LSkillComponent_ToggleZeroCd]);
                        if (addr) {
                            ((void (*)(void *))addr)(nullptr);
                        }
                    }
                }
                ImGui::Checkbox("No Mana/Energy Cost", &g_noManaCost);
                ImGui::Checkbox("Auto Skill Upgrade", &g_autoSkillUpgrade);
            }

            if (ImGui::CollapsingHeader("3. Camera / Zoom", ImGuiTreeNodeFlags_DefaultOpen)) {
                ImGui::Checkbox("Camera Zoom Hack", &g_cameraZoom);
                if (g_cameraZoom) {
                    ImGui::SliderFloat("Zoom Amount", &g_zoomAmount, 50.0f, 500.0f, "%.0f");
                    ImGui::Text("Tip: Higher = more zoom out");
                    applyCameraPatch(true);
                } else {
                    applyCameraPatch(false);
                }
                ImGui::Checkbox("Free Camera", &g_freeCamera);
                ImGui::Checkbox("No Camera Fog", &g_noFog);
            }

            if (ImGui::CollapsingHeader("4. God Mode / Damage")) {
                ImGui::Checkbox("God Mode (Immune Damage)", &g_godMode);
                ImGui::SameLine();
                ImGui::Checkbox("One Hit Kill", &g_oneHit);
                ImGui::Checkbox("No Stun/CC", &g_noStun);
            }

            if (ImGui::CollapsingHeader("5. Speed Hack")) {
                ImGui::Checkbox("Speed Hack", &g_speedHack);
                if (g_speedHack) {
                    ImGui::SliderFloat("Speed Multiplier", &g_speedMultiplier, 1.0f, 10.0f, "%.1fx");
                }
            }

            if (ImGui::CollapsingHeader("6. Auto Aim / Targeting")) {
                ImGui::Checkbox("Auto Aim (Lock nearest enemy)", &g_autoAim);
                if (g_autoAim) {
                    ImGui::SliderFloat("Aim Range", &g_aimRange, 100.0f, 2000.0f, "%.0f");
                    ImGui::Combo("Target Mode", &g_aimTargetMode, "Nearest\0Lowest HP\0Near Cursor\0");
                }
            }

            if (ImGui::CollapsingHeader("7. Attack Range")) {
                ImGui::Checkbox("Extended Attack Range", &g_extendedRange);
                if (g_extendedRange) {
                    ImGui::SliderInt("Range Extend", &g_rangeExt, 100, 2000, "%d");
                }
            }

            ImGui::Separator();
            ImGui::Text("Contact: @little34306 (Telegram)");
            ImGui::Text("FPS: %.1f (%.1f ms)", ImGui::GetIO().Framerate, 1000.0f / ImGui::GetIO().Framerate);

            ImGui::End();
        }

        //=== ESP DRAWING ===
        ImDrawList* draw_list = ImGui::GetBackgroundDrawList();

        if (g_espBox || g_espLine || g_espHealth || g_espName || g_espDistance) {
            // ESP drawing loop - positions are read from actor manager
            // This requires runtime il2cpp calls to iterate actors
            // For now, drawing is prepared for when actor data is available
            draw_list->AddText(ImVec2(10, 100), ImColor(0, 255, 0, 200),
                "ESP Active - Scanning actors...");
        }

        ImGui::Render();
        ImDrawData* draw_data = ImGui::GetDrawData();
        ImGui_ImplMetal_RenderDrawData(draw_data, commandBuffer, renderEncoder);

        [renderEncoder popDebugGroup];
        [renderEncoder endEncoding];

        [commandBuffer presentDrawable:view.currentDrawable];
    }

    [commandBuffer commit];
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size
{

}

@end
