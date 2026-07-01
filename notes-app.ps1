<#
    Notes - Lightweight Always-On-Top Note Taking App for Windows 11
    Built with WPF via PowerShell. All notes saved as .md in /notes subfolder.
    
    Shortcuts:
      Ctrl+N         New note
      Ctrl+W         Close tab
      Ctrl+S         Force save
      Ctrl+Tab       Next tab
      Ctrl+Shift+Tab Previous tab
      Ctrl+M         Zen mode (minimal overlay)
      Ctrl+B         Toggle tab bar
      Escape         Exit zen mode
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ===================== CONFIGURATION =====================
$script:NotesDir   = Join-Path $PSScriptRoot "notes"
$script:AutoSaveMs = 1500
if (!(Test-Path $script:NotesDir)) { New-Item $script:NotesDir -ItemType Directory -Force | Out-Null }

# Clean up empty Untitled files from previous sessions
Get-ChildItem $script:NotesDir -Filter 'Untitled*.md' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $c = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
    if (-not $c.Trim()) { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
}

# ===================== STATE =====================
$script:Tabs             = [System.Collections.ArrayList]::new()
$script:ActiveTab        = -1
$script:IsPinned         = $true
$script:IgnoreTextChange = $false
$script:SortMode         = 0
$script:SortLabels       = @("Name A-Z", "Name Z-A", "Modified", "Created")
$script:SaveTimer        = $null
$script:InfoTimer        = $null
$script:InfoUpdateMs     = 300
$script:EditorUndoLimit  = 30
$script:SidebarVisible   = $true
$script:TabBarVisible    = $true
$script:ZenMode          = $false
$script:SavedSidebarWidth = $null
$script:Chrome           = $null

# ===================== XAML =====================
$xamlString = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Notes" Width="880" Height="620" MinWidth="480" MinHeight="200"
        WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True"
        SnapsToDevicePixels="True" UseLayoutRounding="True">

    <Window.Resources>
        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#2E2E58"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="#E0E0F0"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightBrushKey}" Color="#242448"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightTextBrushKey}" Color="#B0B0D0"/>

        <Style x:Key="WinBtn" TargetType="Button">
            <Setter Property="Width" Value="34"/>
            <Setter Property="Height" Value="26"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#9090B0"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bg" Background="{TemplateBinding Background}" CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#2E2E52"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="WinBtnClose" TargetType="Button" BasedOn="{StaticResource WinBtn}">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bg" Background="{TemplateBinding Background}" CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#C04050"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ToolBtn" TargetType="Button">
            <Setter Property="Height" Value="24"/>
            <Setter Property="Background" Value="#1E1E3A"/>
            <Setter Property="Foreground" Value="#8888AA"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="Padding" Value="8,2"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bg" Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#2E2E52"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="TreeViewItem">
            <Setter Property="Foreground" Value="#C0C0D8"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="3,2"/>
        </Style>
    </Window.Resources>

    <Border Name="MainBorder" Background="#151528" CornerRadius="8" BorderBrush="#2A2A4E" BorderThickness="1">
        <Grid Name="MainGrid">
            <Grid.RowDefinitions>
                <RowDefinition Name="TitleRowDef" Height="34"/>
                <RowDefinition Name="TabBarRowDef" Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Name="StatusRowDef" Height="24"/>
            </Grid.RowDefinitions>

            <!-- TITLE BAR -->
            <Border Name="TitleBar" Grid.Row="0" Background="#101020" CornerRadius="8,8,0,0">
                <DockPanel Name="TitleContent" Margin="10,0,4,0">
                    <TextBlock Name="TitleText" Text="&#x2726; Notes" VerticalAlignment="Center" Foreground="#7B6FF0" FontSize="13" FontWeight="SemiBold" FontFamily="Segoe UI"/>
                    <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                        <Button Name="BtnZen" Content="&#x25A1;" Style="{StaticResource WinBtn}" ToolTip="Zen Mode (Ctrl+M)" FontSize="13"/>
                        <Button Name="BtnSidebar" Content="&#x2261;" Style="{StaticResource WinBtn}" ToolTip="Toggle Sidebar" FontSize="15"/>
                        <Button Name="BtnTabBar" Content="&#x25BD;" Style="{StaticResource WinBtn}" ToolTip="Toggle Tab Bar (Ctrl+B)" FontSize="10"/>
                        <Button Name="BtnPin" Content="&#x2022;" Style="{StaticResource WinBtn}" ToolTip="Always on Top (On)" FontSize="18"/>
                        <Button Name="BtnMin" Content="&#x2014;" Style="{StaticResource WinBtn}" ToolTip="Minimize"/>
                        <Button Name="BtnClose" Content="&#x2715;" Style="{StaticResource WinBtnClose}" ToolTip="Close"/>
                    </StackPanel>
                </DockPanel>
            </Border>

            <!-- ZEN MODE STRIP (hidden by default, shown in zen mode) -->
            <Border Name="ZenStrip" Grid.Row="0" Background="#7B6FF0" CornerRadius="8,8,0,0" Height="6"
                    VerticalAlignment="Top" Visibility="Collapsed" ToolTip="Ctrl+M or Esc to exit Zen mode &#x000A;Drag to move"/>

            <!-- TAB BAR -->
            <Border Name="TabBarBorder" Grid.Row="1" Background="#1A1A32" Padding="6,4,6,0" BorderBrush="#222244" BorderThickness="0,0,0,1">
                <DockPanel>
                    <Button Name="BtnNewTab" DockPanel.Dock="Right" Content="+" Style="{StaticResource WinBtn}" Width="28" Height="24" FontSize="14" ToolTip="New Note (Ctrl+N)" VerticalAlignment="Bottom" Margin="2,0,0,0"/>
                    <ScrollViewer HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Disabled">
                        <StackPanel Name="TabBar" Orientation="Horizontal"/>
                    </ScrollViewer>
                </DockPanel>
            </Border>

            <!-- CONTENT -->
            <Grid Grid.Row="2">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Name="SidebarCol" Width="200" MinWidth="0"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*" MinWidth="200"/>
                </Grid.ColumnDefinitions>

                <Border Name="SidebarBorder" Grid.Column="0" Background="#101020" BorderBrush="#222244" BorderThickness="0,0,1,0">
                    <DockPanel>
                        <Border DockPanel.Dock="Top" Padding="8,6" BorderBrush="#222244" BorderThickness="0,0,0,1">
                            <StackPanel>
                                <DockPanel Margin="0,0,0,4">
                                    <TextBlock Text="EXPLORER" Foreground="#555578" FontSize="10" FontWeight="Bold" VerticalAlignment="Center" FontFamily="Segoe UI"/>
                                    <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" HorizontalAlignment="Right">
                                        <Button Name="BtnNewNote" Content="+" Style="{StaticResource ToolBtn}" Width="24" Padding="0" ToolTip="New Note" Margin="0,0,3,0" FontSize="14"/>
                                        <Button Name="BtnNewFolder" Content="&#x25A2;" Style="{StaticResource ToolBtn}" Width="24" Padding="0" ToolTip="New Folder"/>
                                    </StackPanel>
                                </DockPanel>
                                <Button Name="BtnSort" Content="&#x2195; Name A-Z" Style="{StaticResource ToolBtn}" HorizontalAlignment="Stretch" ToolTip="Click to change sort order"/>
                            </StackPanel>
                        </Border>
                        <TreeView Name="FileTree" Background="Transparent" BorderThickness="0" Padding="4,4"/>
                    </DockPanel>
                </Border>

                <GridSplitter Name="Splitter" Grid.Column="1" Width="3" Background="#222244" HorizontalAlignment="Center" VerticalAlignment="Stretch"/>

                <Border Grid.Column="2" Background="#151528">
                    <TextBox Name="Editor"
                        AcceptsReturn="True" AcceptsTab="True" TextWrapping="Wrap"
                        VerticalScrollBarVisibility="Auto"
                        Background="Transparent" Foreground="#D8D8F0"
                        CaretBrush="#7B6FF0" SelectionBrush="#4040A0"
                        BorderThickness="0" Padding="20,14"
                        FontFamily="Cascadia Code,Consolas,Courier New" FontSize="14"
                        UndoLimit="30"
                        IsEnabled="False"/>
                </Border>
            </Grid>

            <!-- STATUS BAR -->
            <Border Name="StatusBarBorder" Grid.Row="3" Background="#0E0E1E" CornerRadius="0,0,8,8" Padding="10,0">
                <DockPanel VerticalAlignment="Center">
                    <TextBlock Name="StatusText" Text="Ready" Foreground="#444466" FontSize="10.5" FontFamily="Segoe UI"/>
                    <TextBlock Name="InfoText" Text="" Foreground="#444466" FontSize="10.5" FontFamily="Segoe UI" HorizontalAlignment="Right" DockPanel.Dock="Right"/>
                </DockPanel>
            </Border>
        </Grid>
    </Border>
</Window>
'@

# ===================== CREATE WINDOW =====================
[xml]$xaml = $xamlString
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$script:Chrome = [System.Windows.Shell.WindowChrome]::new()
$script:Chrome.CaptionHeight = 34
$script:Chrome.ResizeBorderThickness = [System.Windows.Thickness]::new(6)
$script:Chrome.GlassFrameThickness  = [System.Windows.Thickness]::new(0)
$script:Chrome.CornerRadius          = [System.Windows.CornerRadius]::new(8)
[System.Windows.Shell.WindowChrome]::SetWindowChrome($window, $script:Chrome)

# ===================== CONTROL REFERENCES =====================
$mainBorder      = $window.FindName('MainBorder')
$mainGrid        = $window.FindName('MainGrid')
$titleBar        = $window.FindName('TitleBar')
$titleContent    = $window.FindName('TitleContent')
$titleText       = $window.FindName('TitleText')
$zenStrip        = $window.FindName('ZenStrip')
$titleRowDef     = $window.FindName('TitleRowDef')
$tabBarRowDef    = $window.FindName('TabBarRowDef')
$statusRowDef    = $window.FindName('StatusRowDef')
$btnZen          = $window.FindName('BtnZen')
$btnSidebar      = $window.FindName('BtnSidebar')
$btnTabBar       = $window.FindName('BtnTabBar')
$btnPin          = $window.FindName('BtnPin')
$btnMin          = $window.FindName('BtnMin')
$btnClose        = $window.FindName('BtnClose')
$btnNewTab       = $window.FindName('BtnNewTab')
$tabBar          = $window.FindName('TabBar')
$tabBarBorder    = $window.FindName('TabBarBorder')
$btnNewNote      = $window.FindName('BtnNewNote')
$btnNewFolder    = $window.FindName('BtnNewFolder')
$btnSort         = $window.FindName('BtnSort')
$fileTree        = $window.FindName('FileTree')
$editor          = $window.FindName('Editor')
$statusText      = $window.FindName('StatusText')
$infoText        = $window.FindName('InfoText')
$sidebarCol      = $window.FindName('SidebarCol')
$sidebarBorder   = $window.FindName('SidebarBorder')
$splitter        = $window.FindName('Splitter')
$statusBarBorder = $window.FindName('StatusBarBorder')

$editor.UndoLimit = $script:EditorUndoLimit

# Make buttons clickable through WindowChrome caption area
foreach ($btn in @($btnZen, $btnSidebar, $btnTabBar, $btnPin, $btnMin, $btnClose, $btnNewTab)) {
    [System.Windows.Shell.WindowChrome]::SetIsHitTestVisibleInChrome($btn, $true)
}

# ===================== UTILITY FUNCTIONS =====================
function Set-Status ([string]$msg) { $statusText.Text = $msg }

function Get-TextStats ([string]$text) {
    if ([string]::IsNullOrEmpty($text)) {
        return [pscustomobject]@{ Lines = 1; Words = 0 }
    }

    $lines = 1
    $words = 0
    $inWord = $false

    for ($i = 0; $i -lt $text.Length; $i++) {
        $ch = $text[$i]
        if ($ch -eq "`n") { $lines++ }

        if ([char]::IsWhiteSpace($ch)) {
            $inWord = $false
        } elseif (-not $inWord) {
            $words++
            $inWord = $true
        }
    }

    return [pscustomobject]@{ Lines = $lines; Words = $words }
}

function Update-Info {
    if ($script:ActiveTab -ge 0 -and $script:ActiveTab -lt $script:Tabs.Count) {
        $stats = Get-TextStats $editor.Text
        $infoText.Text = "Ln $($stats.Lines)  |  $($stats.Words) words"
    } else { $infoText.Text = '' }
}

function Request-InfoUpdate {
    if ($script:InfoTimer) {
        $script:InfoTimer.Stop()
        $script:InfoTimer.Start()
    } else {
        Update-Info
    }
}

function Clear-EditorUndo {
    try { $editor.ClearUndo() } catch {}
}

function Get-UniquePath ([string]$dir, [string]$base) {
    $p = Join-Path $dir "$base.md"
    $i = 1
    while (Test-Path $p) { $p = Join-Path $dir "$base ($i).md"; $i++ }
    return $p
}

function Show-InputDialog ([string]$title, [string]$label, [string]$default) {
    $dlg = [System.Windows.Window]::new()
    $dlg.Title = $title; $dlg.Width = 340; $dlg.Height = 150
    $dlg.WindowStartupLocation = 'CenterOwner'; $dlg.Owner = $window
    $dlg.WindowStyle = 'ToolWindow'; $dlg.Topmost = $true
    $dlg.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#1E1E38'))

    $sp = [System.Windows.Controls.StackPanel]::new()
    $sp.Margin = [System.Windows.Thickness]::new(16)

    $lbl = [System.Windows.Controls.TextBlock]::new()
    $lbl.Text = $label; $lbl.FontSize = 12
    $lbl.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#C0C0E0'))
    $lbl.Margin = [System.Windows.Thickness]::new(0,0,0,6)
    $sp.AddChild($lbl)

    $tb = [System.Windows.Controls.TextBox]::new()
    $tb.Text = $default; $tb.FontSize = 13
    $tb.Padding = [System.Windows.Thickness]::new(6,4)
    $tb.Background  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#121224'))
    $tb.Foreground  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#E0E0F0'))
    $tb.BorderBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#3A3A60'))
    $tb.CaretBrush  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#7B6FF0'))
    $tb.SelectAll()
    $sp.AddChild($tb)

    $ok = [System.Windows.Controls.Button]::new()
    $ok.Content = 'OK'; $ok.Width = 70; $ok.Height = 28
    $ok.Margin = [System.Windows.Thickness]::new(0,10,0,0)
    $ok.HorizontalAlignment = 'Right'; $ok.Cursor = [System.Windows.Input.Cursors]::Hand
    $ok.Background  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#5A50C0'))
    $ok.Foreground  = [System.Windows.Media.Brushes]::White
    $ok.BorderThickness = [System.Windows.Thickness]::new(0)
    $sp.AddChild($ok)

    $script:_dlgResult = $null
    $ok.Add_Click({ $script:_dlgResult = $tb.Text.Trim(); $dlg.Close() }.GetNewClosure())
    $tb.Add_KeyDown({
        param($s,$e)
        if ($e.Key -eq 'Return') { $script:_dlgResult = $tb.Text.Trim(); $dlg.Close() }
    }.GetNewClosure())

    $dlg.Content = $sp
    $dlg.Add_ContentRendered({ $tb.Focus() | Out-Null }.GetNewClosure())
    $dlg.ShowDialog() | Out-Null
    return $script:_dlgResult
}

# ===================== ZEN MODE =====================
function Toggle-ZenMode {
    $script:ZenMode = -not $script:ZenMode

    if ($script:ZenMode) {
        # Enter zen mode - hide everything except editor + thin strip
        $titleContent.Visibility    = 'Collapsed'
        $zenStrip.Visibility        = 'Visible'
        $titleRowDef.Height         = [System.Windows.GridLength]::new(6)
        $tabBarBorder.Visibility    = 'Collapsed'
        $statusBarBorder.Visibility = 'Collapsed'
        $statusRowDef.Height        = [System.Windows.GridLength]::new(0)

        # Hide sidebar
        if ($script:SidebarVisible) {
            $script:SavedSidebarWidth = $sidebarCol.Width
        }
        $sidebarCol.Width    = [System.Windows.GridLength]::new(0)
        $sidebarCol.MinWidth = 0
        $sidebarBorder.Visibility = 'Collapsed'
        $splitter.Visibility      = 'Collapsed'

        # Shrink chrome caption and disable top resize so strip is drag-only
        $script:Chrome.CaptionHeight = 6
        $script:Chrome.ResizeBorderThickness = [System.Windows.Thickness]::new(6, 0, 6, 6)

        # Reduce editor padding for more space
        $editor.Padding = [System.Windows.Thickness]::new(16,10)

        $btnZen.Content = [char]0x25A0  # filled square
        Set-Status ''
    } else {
        # Exit zen mode - restore everything
        $titleContent.Visibility    = 'Visible'
        $zenStrip.Visibility        = 'Collapsed'
        $titleRowDef.Height         = [System.Windows.GridLength]::new(34)
        $statusBarBorder.Visibility = 'Visible'
        $statusRowDef.Height        = [System.Windows.GridLength]::new(24)

        # Restore tab bar based on its own toggle state
        if ($script:TabBarVisible) {
            $tabBarBorder.Visibility = 'Visible'
        }

        # Restore sidebar based on its own toggle state
        if ($script:SidebarVisible) {
            $sidebarCol.Width    = if ($script:SavedSidebarWidth) { $script:SavedSidebarWidth } else { [System.Windows.GridLength]::new(200) }
            $sidebarCol.MinWidth = 140
            $sidebarBorder.Visibility = 'Visible'
            $splitter.Visibility      = 'Visible'
        }

        $script:Chrome.CaptionHeight = 34
        $script:Chrome.ResizeBorderThickness = [System.Windows.Thickness]::new(6)
        $editor.Padding = [System.Windows.Thickness]::new(20,14)

        $btnZen.Content = [char]0x25A1  # empty square
        Set-Status 'Ready'
    }
    $editor.Focus() | Out-Null
}

function Toggle-TabBar {
    if ($script:ZenMode) { return }  # Don't toggle independently in zen mode
    $script:TabBarVisible = -not $script:TabBarVisible
    if ($script:TabBarVisible) {
        $tabBarBorder.Visibility = 'Visible'
        $btnTabBar.Content = [char]0x25BD  # down triangle
        $btnTabBar.ToolTip = 'Hide Tab Bar (Ctrl+B)'
    } else {
        $tabBarBorder.Visibility = 'Collapsed'
        $btnTabBar.Content = [char]0x25B7  # right triangle
        $btnTabBar.ToolTip = 'Show Tab Bar (Ctrl+B)'
    }
}

function Toggle-Sidebar {
    if ($script:ZenMode) { return }
    $script:SidebarVisible = -not $script:SidebarVisible
    if ($script:SidebarVisible) {
        $sidebarCol.Width    = if ($script:SavedSidebarWidth) { $script:SavedSidebarWidth } else { [System.Windows.GridLength]::new(200) }
        $sidebarCol.MinWidth = 140
        $sidebarBorder.Visibility = 'Visible'
        $splitter.Visibility      = 'Visible'
    } else {
        $script:SavedSidebarWidth = $sidebarCol.Width
        $sidebarCol.Width    = [System.Windows.GridLength]::new(0)
        $sidebarCol.MinWidth = 0
        $sidebarBorder.Visibility = 'Collapsed'
        $splitter.Visibility      = 'Collapsed'
    }
}

# ===================== SAVE / LOAD =====================
function Save-ActiveTab {
    if ($script:ActiveTab -lt 0 -or $script:ActiveTab -ge $script:Tabs.Count) { return }
    $tab = $script:Tabs[$script:ActiveTab]
    $tab.Content = $editor.Text

    # Skip saving empty untitled notes (no file on disk yet or empty content)
    if (-not $tab.FilePath -and -not $tab.Content.Trim()) { return }

    # Create file path on first real save (lazy creation)
    if (-not $tab.FilePath) {
        $tab.FilePath = Get-UniquePath $script:NotesDir 'Untitled'
        $tab.Title = [System.IO.Path]::GetFileNameWithoutExtension($tab.FilePath)
        Update-TabVisual $script:ActiveTab
        Refresh-Sidebar
    }

    $dir = Split-Path $tab.FilePath -Parent
    if (!(Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($tab.FilePath, $tab.Content, [System.Text.Encoding]::UTF8)
    $tab.IsDirty = $false
    Update-TabVisual $script:ActiveTab
    Set-Status "Saved"
}

# ===================== TAB MANAGEMENT =====================
function Update-TabVisual ([int]$idx) {
    if ($idx -lt 0 -or $idx -ge $script:Tabs.Count) { return }
    $tab = $script:Tabs[$idx]
    $title = $tab.Title
    if ($tab.IsDirty) { $title = [char]0x25CF + " $title" }
    $tab.TitleBlock.Text = $title

    $active  = ($idx -eq $script:ActiveTab)
    $bgColor = if ($active) { '#262648' } else { '#1A1A32' }
    $fgColor = if ($active) { '#E0E0F0' } else { '#7878A0' }
    $tab.Element.Background    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString($bgColor))
    $tab.TitleBlock.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString($fgColor))
}

function Build-TabElement ([int]$idx) {
    $tab = $script:Tabs[$idx]

    $border = [System.Windows.Controls.Border]::new()
    $border.CornerRadius = [System.Windows.CornerRadius]::new(6,6,0,0)
    $border.Padding      = [System.Windows.Thickness]::new(10,5,5,5)
    $border.Margin       = [System.Windows.Thickness]::new(0,0,2,0)
    $border.Cursor       = [System.Windows.Input.Cursors]::Hand
    $border.Background   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#1A1A32'))

    $sp = [System.Windows.Controls.StackPanel]::new()
    $sp.Orientation = 'Horizontal'

    $txt = [System.Windows.Controls.TextBlock]::new()
    $txt.Text = $tab.Title; $txt.FontSize = 11.5; $txt.MaxWidth = 130
    $txt.TextTrimming = 'CharacterEllipsis'; $txt.VerticalAlignment = 'Center'
    $txt.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
    $txt.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#9090B0'))

    $closeBtn = [System.Windows.Controls.Button]::new()
    $closeBtn.Content = [char]0x2715; $closeBtn.FontSize = 9
    $closeBtn.Width = 18; $closeBtn.Height = 18
    $closeBtn.Margin = [System.Windows.Thickness]::new(6,0,0,0)
    $closeBtn.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#606080'))
    $closeBtn.Background = [System.Windows.Media.Brushes]::Transparent
    $closeBtn.BorderThickness = [System.Windows.Thickness]::new(0)
    $closeBtn.Cursor = [System.Windows.Input.Cursors]::Hand; $closeBtn.VerticalAlignment = 'Center'
    $closeBtn.Template = [System.Windows.Markup.XamlReader]::Parse("<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' TargetType='Button'><Border x:Name='bg' Background='{TemplateBinding Background}' CornerRadius='3'><ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/></Border><ControlTemplate.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='bg' Property='Background' Value='#3A3A5A'/></Trigger></ControlTemplate.Triggers></ControlTemplate>")
    [System.Windows.Shell.WindowChrome]::SetIsHitTestVisibleInChrome($closeBtn, $true)

    $closeBtn.Tag = $border
    $closeBtn.Add_Click({
        param($s,$e)
        $parentBorder = $s.Tag
        $ci = $tabBar.Children.IndexOf($parentBorder)
        if ($ci -ge 0) { Close-Tab $ci }
    }.GetNewClosure())

    $sp.AddChild($txt); $sp.AddChild($closeBtn)
    $border.Child = $sp
    [System.Windows.Shell.WindowChrome]::SetIsHitTestVisibleInChrome($border, $true)

    $border.Add_MouseLeftButtonDown({
        param($s,$e)
        $ci = $tabBar.Children.IndexOf($s)
        if ($ci -ge 0) { Switch-Tab $ci }
        $e.Handled = $true
    }.GetNewClosure())

    $tab.Element    = $border
    $tab.TitleBlock = $txt
    return $border
}

function Switch-Tab ([int]$idx) {
    if ($idx -lt 0 -or $idx -ge $script:Tabs.Count) { return }
    if ($script:ActiveTab -ge 0 -and $script:ActiveTab -lt $script:Tabs.Count) {
        $script:Tabs[$script:ActiveTab].Content = $editor.Text
    }
    $old = $script:ActiveTab
    $script:ActiveTab = $idx
    $script:IgnoreTextChange = $true
    $editor.Text = $script:Tabs[$idx].Content
    Clear-EditorUndo
    $editor.IsEnabled = $true
    $script:IgnoreTextChange = $false
    if ($old -ge 0 -and $old -lt $script:Tabs.Count) { Update-TabVisual $old }
    Update-TabVisual $idx
    Update-Info
    Set-Status "Editing: $($script:Tabs[$idx].Title)"
    $editor.Focus() | Out-Null
}

function Add-NoteTab ($filePath = $null, [string]$content = '', [bool]$switchTo = $true) {
    # Don't open duplicate tabs for the same file
    if ($filePath) {
        for ($i = 0; $i -lt $script:Tabs.Count; $i++) {
            if ($script:Tabs[$i].FilePath -eq $filePath) { if ($switchTo) { Switch-Tab $i }; return }
        }
    }
    $title = if ($filePath) { [System.IO.Path]::GetFileNameWithoutExtension($filePath) } else { 'Untitled' }
    $tab = @{ FilePath=$filePath; Title=$title; Content=$content; IsDirty=$false; Element=$null; TitleBlock=$null }
    $idx = $script:Tabs.Add($tab)
    $el = Build-TabElement $idx
    $tabBar.Children.Add($el) | Out-Null
    if ($switchTo) { Switch-Tab $idx }
}

function Release-TabResources ($tab) {
    if (-not $tab) { return }

    if ($tab.Element) {
        try { $tab.Element.Child = $null } catch {}
    }

    $tab.Element = $null
    $tab.TitleBlock = $null
    $tab.Content = $null
}

function Remove-TabAt ([int]$idx) {
    if ($idx -lt 0 -or $idx -ge $script:Tabs.Count) { return }
    $tab = $script:Tabs[$idx]

    if ($idx -lt $tabBar.Children.Count) {
        $tabBar.Children.RemoveAt($idx)
    }
    Release-TabResources $tab
    $script:Tabs.RemoveAt($idx)
}

function Close-Tab ([int]$idx) {
    if ($idx -lt 0 -or $idx -ge $script:Tabs.Count) { return }
    $tab = $script:Tabs[$idx]

    # Update content if this is the active tab
    if ($idx -eq $script:ActiveTab) { $tab.Content = $editor.Text }

    # Handle file cleanup
    if ($tab.FilePath) {
        if ($tab.Title -match '^Untitled' -and -not $tab.Content.Trim()) {
            # Delete empty Untitled file from disk
            Remove-Item $tab.FilePath -Force -ErrorAction SilentlyContinue
        } elseif ($tab.IsDirty) {
            # Save dirty non-empty tab
            [System.IO.File]::WriteAllText($tab.FilePath, $tab.Content, [System.Text.Encoding]::UTF8)
        }
    }
    # No file on disk for unsaved empty tabs - nothing to clean up

    Remove-TabAt $idx

    if ($script:Tabs.Count -eq 0) {
        $script:ActiveTab = -1
        # Create a virtual tab (no file on disk)
        Add-NoteTab $null '' $true
        Refresh-Sidebar
    } else {
        if ($script:ActiveTab -gt $idx) { $script:ActiveTab-- }
        elseif ($script:ActiveTab -eq $idx) { $script:ActiveTab = [Math]::Min($idx, $script:Tabs.Count - 1) }
        if ($script:ActiveTab -ge $script:Tabs.Count) { $script:ActiveTab = $script:Tabs.Count - 1 }
        Switch-Tab $script:ActiveTab
    }
}

function New-Note ([string]$folder = $script:NotesDir) {
    # Reuse an existing empty Untitled tab instead of creating a new one
    for ($i = 0; $i -lt $script:Tabs.Count; $i++) {
        $t = $script:Tabs[$i]
        if ($t.Title -match '^Untitled' -and -not $t.Content.Trim()) {
            Switch-Tab $i; return
        }
    }
    # Create a virtual tab (file created lazily on first real save)
    Add-NoteTab $null '' $true
}

# ===================== SIDEBAR =====================
function Get-SortedItems ($items) {
    switch ($script:SortMode) {
        0 { $items | Sort-Object Name }
        1 { $items | Sort-Object Name -Descending }
        2 { $items | Sort-Object LastWriteTime -Descending }
        3 { $items | Sort-Object CreationTime -Descending }
    }
}

function Add-FileContextMenu ($treeItem, $filePath) {
    $cm = [System.Windows.Controls.ContextMenu]::new()

    $miRen = [System.Windows.Controls.MenuItem]::new()
    $miRen.Header = 'Rename'; $miRen.Tag = $filePath
    $miRen.Add_Click({
        param($s,$e)
        $fp = $s.Tag; $cur = [System.IO.Path]::GetFileNameWithoutExtension($fp)
        $newName = Show-InputDialog 'Rename Note' 'New name:' $cur
        if ($newName -and $newName -ne $cur) {
            $dir = Split-Path $fp -Parent
            $np = Join-Path $dir "$newName.md"
            if (!(Test-Path $np)) {
                Rename-Item $fp (Split-Path $np -Leaf) -Force
                foreach ($t in $script:Tabs) {
                    if ($t.FilePath -eq $fp) { $t.FilePath = $np; $t.Title = $newName }
                }
                for ($i=0; $i -lt $script:Tabs.Count; $i++) { Update-TabVisual $i }
                Refresh-Sidebar
            }
        }
    }.GetNewClosure())
    $cm.Items.Add($miRen) | Out-Null

    $miDel = [System.Windows.Controls.MenuItem]::new()
    $miDel.Header = 'Delete'; $miDel.Tag = $filePath
    $miDel.Add_Click({
        param($s,$e)
        $fp = $s.Tag
        $name = [System.IO.Path]::GetFileNameWithoutExtension($fp)
        $r = [System.Windows.MessageBox]::Show("Delete note '$name'?`nThis cannot be undone.", 'Confirm Delete', 'YesNo', 'Warning')
        if ($r -eq 'Yes') {
            for ($i = $script:Tabs.Count-1; $i -ge 0; $i--) {
                if ($script:Tabs[$i].FilePath -eq $fp) {
                    Remove-TabAt $i
                    if ($script:ActiveTab -ge $i) { $script:ActiveTab-- }
                }
            }
            Remove-Item $fp -Force
            if ($script:Tabs.Count -eq 0) {
                $script:ActiveTab = -1; Add-NoteTab $null '' $true
            } elseif ($script:ActiveTab -ge $script:Tabs.Count) {
                $script:ActiveTab = $script:Tabs.Count - 1; Switch-Tab $script:ActiveTab
            } elseif ($script:ActiveTab -ge 0) { Switch-Tab $script:ActiveTab }
            Refresh-Sidebar
        }
    }.GetNewClosure())
    $cm.Items.Add($miDel) | Out-Null
    $treeItem.ContextMenu = $cm
}

function Add-FolderContextMenu ($treeItem, $folderPath) {
    $cm = [System.Windows.Controls.ContextMenu]::new()

    $miNew = [System.Windows.Controls.MenuItem]::new()
    $miNew.Header = 'New Note Here'; $miNew.Tag = $folderPath
    $miNew.Add_Click({
        param($s,$e)
        $folder = $s.Tag
        $path = Get-UniquePath $folder 'Untitled'
        [System.IO.File]::WriteAllText($path, '', [System.Text.Encoding]::UTF8)
        Add-NoteTab $path '' $true
        Refresh-Sidebar
    }.GetNewClosure())
    $cm.Items.Add($miNew) | Out-Null

    $miRen = [System.Windows.Controls.MenuItem]::new()
    $miRen.Header = 'Rename Folder'; $miRen.Tag = $folderPath
    $miRen.Add_Click({
        param($s,$e)
        $fp = $s.Tag; $cur = [System.IO.Path]::GetFileName($fp)
        $newName = Show-InputDialog 'Rename Folder' 'New folder name:' $cur
        if ($newName -and $newName -ne $cur) {
            $parent = Split-Path $fp -Parent
            $np = Join-Path $parent $newName
            if (!(Test-Path $np)) {
                Rename-Item $fp $newName -Force
                foreach ($t in $script:Tabs) {
                    if ($t.FilePath -and $t.FilePath.StartsWith($fp)) {
                        $t.FilePath = $t.FilePath.Replace($fp, $np)
                    }
                }
                Refresh-Sidebar
            }
        }
    }.GetNewClosure())
    $cm.Items.Add($miRen) | Out-Null

    $miDel = [System.Windows.Controls.MenuItem]::new()
    $miDel.Header = 'Delete Folder'; $miDel.Tag = $folderPath
    $miDel.Add_Click({
        param($s,$e)
        $fp = $s.Tag; $name = [System.IO.Path]::GetFileName($fp)
        $r = [System.Windows.MessageBox]::Show("Delete folder '$name' and all contents?`nThis cannot be undone.", 'Confirm Delete', 'YesNo', 'Warning')
        if ($r -eq 'Yes') {
            for ($i = $script:Tabs.Count-1; $i -ge 0; $i--) {
                if ($script:Tabs[$i].FilePath -and $script:Tabs[$i].FilePath.StartsWith($fp)) {
                    Remove-TabAt $i
                    if ($script:ActiveTab -ge $i) { $script:ActiveTab-- }
                }
            }
            Remove-Item $fp -Recurse -Force
            if ($script:Tabs.Count -eq 0) {
                $script:ActiveTab = -1; Add-NoteTab $null '' $true
            } elseif ($script:ActiveTab -ge $script:Tabs.Count) {
                $script:ActiveTab = $script:Tabs.Count - 1; Switch-Tab $script:ActiveTab
            } elseif ($script:ActiveTab -ge 0) { Switch-Tab $script:ActiveTab }
            Refresh-Sidebar
        }
    }.GetNewClosure())
    $cm.Items.Add($miDel) | Out-Null
    $treeItem.ContextMenu = $cm
}

function Clear-TreeItemResources ([System.Windows.Controls.ItemsControl]$item) {
    foreach ($child in @($item.Items)) {
        if ($child -is [System.Windows.Controls.ItemsControl]) {
            Clear-TreeItemResources $child
        }
    }

    if ($item -is [System.Windows.Controls.TreeViewItem]) {
        $item.ContextMenu = $null
    }

    $item.Items.Clear()
}

function Clear-SidebarTree {
    foreach ($item in @($fileTree.Items)) {
        if ($item -is [System.Windows.Controls.ItemsControl]) {
            Clear-TreeItemResources $item
        }
    }

    $fileTree.Items.Clear()
}

function Refresh-Sidebar {
    Clear-SidebarTree

    # Folders (using BMP-safe characters)
    $folders = Get-ChildItem $script:NotesDir -Directory -ErrorAction SilentlyContinue
    if ($folders) {
        $folders = Get-SortedItems $folders
        foreach ($folder in $folders) {
            $fi = [System.Windows.Controls.TreeViewItem]::new()
            $fi.Header = "$([char]0x25B8) $($folder.Name)"
            $fi.Tag = $folder.FullName; $fi.IsExpanded = $true
            $fi.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#8888B0'))
            $fi.FontWeight = 'SemiBold'
            Add-FolderContextMenu $fi $folder.FullName

            $files = Get-ChildItem $folder.FullName -Filter '*.md' -File -ErrorAction SilentlyContinue
            if ($files) {
                $files = Get-SortedItems $files
                foreach ($f in $files) {
                    $ni = [System.Windows.Controls.TreeViewItem]::new()
                    $ni.Header = "   $([System.IO.Path]::GetFileNameWithoutExtension($f.Name))"
                    $ni.Tag = $f.FullName; $ni.FontWeight = 'Normal'
                    $ni.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#B8B8D0'))
                    $ni.Add_MouseDoubleClick({
                        param($s,$e)
                        $content = [System.IO.File]::ReadAllText($s.Tag, [System.Text.Encoding]::UTF8)
                        Add-NoteTab $s.Tag $content $true; $e.Handled = $true
                    }.GetNewClosure())
                    Add-FileContextMenu $ni $f.FullName
                    $fi.Items.Add($ni) | Out-Null
                }
            }
            $fileTree.Items.Add($fi) | Out-Null
        }
    }

    # Root-level files
    $rootFiles = Get-ChildItem $script:NotesDir -Filter '*.md' -File -ErrorAction SilentlyContinue
    if ($rootFiles) {
        $rootFiles = Get-SortedItems $rootFiles
        foreach ($f in $rootFiles) {
            $ni = [System.Windows.Controls.TreeViewItem]::new()
            $ni.Header = "$([char]0x25CB) $([System.IO.Path]::GetFileNameWithoutExtension($f.Name))"
            $ni.Tag = $f.FullName
            $ni.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#C8C8E0'))
            $ni.Add_MouseDoubleClick({
                param($s,$e)
                $content = [System.IO.File]::ReadAllText($s.Tag, [System.Text.Encoding]::UTF8)
                Add-NoteTab $s.Tag $content $true; $e.Handled = $true
            }.GetNewClosure())
            Add-FileContextMenu $ni $f.FullName
            $fileTree.Items.Add($ni) | Out-Null
        }
    }
}

# ===================== EVENT HANDLERS =====================

# Window chrome buttons
$btnClose.Add_Click({ $window.Close() })
$btnMin.Add_Click({ $window.WindowState = 'Minimized' })

$btnPin.Add_Click({
    $script:IsPinned = -not $script:IsPinned
    $window.Topmost = $script:IsPinned
    $color = if ($script:IsPinned) { '#7B6FF0' } else { '#505070' }
    $tip   = if ($script:IsPinned) { 'Always on Top (On)' } else { 'Always on Top (Off)' }
    $btnPin.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString($color))
    $btnPin.ToolTip = $tip
})
$btnPin.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#7B6FF0'))

# View toggles
$btnZen.Add_Click({ Toggle-ZenMode })
$btnSidebar.Add_Click({ Toggle-Sidebar })
$btnTabBar.Add_Click({ Toggle-TabBar })

# Tab and sidebar actions
$btnNewTab.Add_Click({ New-Note })
$btnNewNote.Add_Click({ New-Note })

$btnNewFolder.Add_Click({
    $name = Show-InputDialog 'New Folder' 'Folder name:' 'New Folder'
    if ($name) {
        $fp = Join-Path $script:NotesDir $name
        if (!(Test-Path $fp)) { New-Item $fp -ItemType Directory -Force | Out-Null }
        Refresh-Sidebar
    }
})

$btnSort.Add_Click({
    $script:SortMode = ($script:SortMode + 1) % 4
    $btnSort.Content = "$([char]0x2195) $($script:SortLabels[$script:SortMode])"
    Refresh-Sidebar
})

# Editor text change -> mark dirty + reset autosave timer
$editor.Add_TextChanged({
    if ($script:IgnoreTextChange) { return }
    if ($script:ActiveTab -ge 0 -and $script:ActiveTab -lt $script:Tabs.Count) {
        $script:Tabs[$script:ActiveTab].IsDirty = $true
        Update-TabVisual $script:ActiveTab
        Request-InfoUpdate
        if ($script:SaveTimer) { $script:SaveTimer.Stop(); $script:SaveTimer.Start() }
    }
})

# Keyboard shortcuts
$window.Add_KeyDown({
    param($s,$e)
    $ctrl  = $e.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Control
    $shift = $e.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Shift

    # Escape exits zen mode
    if ($e.Key -eq 'Escape' -and $script:ZenMode) {
        Toggle-ZenMode; $e.Handled = $true; return
    }

    if ($ctrl) {
        switch ($e.Key) {
            'N' { New-Note; $e.Handled = $true }
            'W' { if ($script:ActiveTab -ge 0) { Close-Tab $script:ActiveTab }; $e.Handled = $true }
            'S' { Save-ActiveTab; $e.Handled = $true }
            'M' { Toggle-ZenMode; $e.Handled = $true }
            'B' { Toggle-TabBar; $e.Handled = $true }
            'Tab' {
                if ($script:Tabs.Count -gt 1) {
                    if ($shift) {
                        $p = ($script:ActiveTab - 1 + $script:Tabs.Count) % $script:Tabs.Count
                        Switch-Tab $p
                    } else {
                        $n = ($script:ActiveTab + 1) % $script:Tabs.Count
                        Switch-Tab $n
                    }
                }
                $e.Handled = $true
            }
        }
    }
})

# Save all on close, clean up empty Untitled files
$window.Add_Closing({
    if ($script:SaveTimer) { $script:SaveTimer.Stop() }
    if ($script:InfoTimer) { $script:InfoTimer.Stop() }
    for ($i = 0; $i -lt $script:Tabs.Count; $i++) {
        if ($i -eq $script:ActiveTab) { $script:Tabs[$i].Content = $editor.Text }
        $tab = $script:Tabs[$i]
        if ($tab.FilePath) {
            if ($tab.Title -match '^Untitled' -and -not $tab.Content.Trim()) {
                # Delete empty Untitled files
                Remove-Item $tab.FilePath -Force -ErrorAction SilentlyContinue
            } else {
                [System.IO.File]::WriteAllText($tab.FilePath, $tab.Content, [System.Text.Encoding]::UTF8)
            }
        }
        # Virtual tabs without FilePath: nothing to save/clean
    }
})

# Adjust corners on maximize / restore
$window.Add_StateChanged({
    if ($window.WindowState -eq 'Maximized') {
        $mainBorder.CornerRadius = [System.Windows.CornerRadius]::new(0)
        $titleBar.CornerRadius   = [System.Windows.CornerRadius]::new(0)
        $zenStrip.CornerRadius   = [System.Windows.CornerRadius]::new(0)
    } else {
        $mainBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $titleBar.CornerRadius   = [System.Windows.CornerRadius]::new(8,8,0,0)
        $zenStrip.CornerRadius   = [System.Windows.CornerRadius]::new(8,8,0,0)
    }
})

# ===================== AUTOSAVE TIMER =====================
$script:SaveTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:SaveTimer.Interval = [TimeSpan]::FromMilliseconds($script:AutoSaveMs)
$script:SaveTimer.Add_Tick({ $script:SaveTimer.Stop(); Save-ActiveTab })

$script:InfoTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:InfoTimer.Interval = [TimeSpan]::FromMilliseconds($script:InfoUpdateMs)
$script:InfoTimer.Add_Tick({ $script:InfoTimer.Stop(); Update-Info })

# ===================== INITIALIZATION =====================
$existingFiles = Get-ChildItem $script:NotesDir -Filter '*.md' -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($existingFiles) {
    $content = [System.IO.File]::ReadAllText($existingFiles.FullName, [System.Text.Encoding]::UTF8)
    Add-NoteTab $existingFiles.FullName $content $true
} else {
    $welcomePath = Join-Path $script:NotesDir 'Welcome.md'
    $welcomeContent = @"
# Welcome to Notes

Your lightweight, always-on-top note taking app.

## Keyboard Shortcuts
- **Ctrl+N** - New note
- **Ctrl+W** - Close tab
- **Ctrl+S** - Save now
- **Ctrl+Tab / Ctrl+Shift+Tab** - Cycle tabs
- **Ctrl+M** - Zen mode (minimal overlay)
- **Ctrl+B** - Toggle tab bar
- **Escape** - Exit zen mode

## Features
- Autosave after 1.5s of idle typing
- Always-on-top overlay (toggle with pin button)
- Zen mode: strips everything to just the editor
- Organize notes into folders
- Sort by name, date modified, or date created
- Right-click files/folders to rename or delete
- All notes saved as .md files in the /notes folder

Start typing to begin!
"@
    [System.IO.File]::WriteAllText($welcomePath, $welcomeContent, [System.Text.Encoding]::UTF8)
    Add-NoteTab $welcomePath $welcomeContent $true
}

Refresh-Sidebar

# ===================== RUN =====================
$window.ShowDialog() | Out-Null
