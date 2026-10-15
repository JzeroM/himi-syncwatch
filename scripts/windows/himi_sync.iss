; HIMI Windows 安装包脚本（Inno Setup 6）
;
; 由 CI 的 build-windows job 编译：
;   ISCC.exe /DMyAppVersion=<版本> scripts\windows\himi_sync.iss
; 若编译机已备好中文语言文件（compiler:Languages\ChineseSimplified.isl），
; 再追加 /DIncludeChinese=1 启用中文安装界面，否则仅英文。
;
; 产物：build/windows/setup/himi-sync-windows-<版本>-setup.exe
;
; 关键行为：
;   - 安装位置可自定义（DisableDirPage=no 保留「选择安装位置」页）
;   - 「创建桌面快捷方式」复选框，默认勾选（可取消）
;   - 覆盖安装：固定 AppId + CloseApplications/AppMutex，运行中会提示关闭

#define MyAppName "HIMI"
#define MyAppPublisher "himi-syncwatch"
#define MyAppExeName "himi_syncwatch.exe"
#define MyAppIcon "..\..\windows\runner\resources\app_icon.ico"
#define MyAppOutDir "..\..\build\windows\setup"

[Setup]
; 固定 GUID：升级/覆盖安装靠它识别同一应用，切勿随意更改
AppId={{2B67458C-BE83-429C-8EAD-BC444C6CD7E9}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
; 默认装到当前用户目录（无需管理员，可改）
DefaultDirName={autopf}\HIMI
; 保留目录选择页：允许自定义安装位置
DisableDirPage=no
AllowUNCPath=yes
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
Compression=lzma
SolidCompression=yes
OutputDir={#MyAppOutDir}
OutputBaseFilename=himi-sync-windows-{#MyAppVersion}-setup
SetupIconFile={#MyAppIcon}
; 覆盖安装：应用运行中时提示关闭，避免 DLL 被占用
CloseApplications=yes
AllowCloseApplications=yes
AppMutex=himi_syncwatch
MinVersion=6.1

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
#ifdef IncludeChinese
Name: "chs"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#endif

[Tasks]
; 桌面快捷方式复选框，默认勾选（用户可取消）
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; 开始菜单：始终创建
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
; 桌面：仅勾选 desktopicon 时创建
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
