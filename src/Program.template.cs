using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace LotmDiagnosticsTool
{
    public class MainForm : Form
    {
        private TextBox txtGamePath;
        private Button btnBrowse;
        private Button btnAutoDetect;
        private Button btnInstall;
        private Button btnCollect;
        private Button btnUninstall;
        private Button btnOpenLogs;
        private Button btnCopyReport;
        private Label lblStatus;
        private RichTextBox rtbLog;

        private const string EmbeddedModLuaBase64 = "__PAYLOAD_B64__";

        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }

        public MainForm()
        {
            InitializeComponent();
            AutoDetectGamePath();
            CheckCurrentStatus();
        }

        private void InitializeComponent()
        {
            this.Text = "Lord of the Mysteries — Диагностика UI и Шрифтов v1.0.2";
            this.Size = new Size(720, 620);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.FormBorderStyle = FormBorderStyle.FixedSingle;
            this.MaximizeBox = false;
            this.BackColor = Color.FromArgb(20, 24, 30);
            this.ForeColor = Color.FromArgb(220, 225, 235);
            this.Font = new Font("Segoe UI", 9.5f, FontStyle.Regular);

            // Header Banner
            Panel pnlHeader = new Panel
            {
                Location = new Point(0, 0),
                Size = new Size(720, 70),
                BackColor = Color.FromArgb(28, 33, 42)
            };
            Label lblTitle = new Label
            {
                Text = "Lord of the Mysteries — Диагностика UI и Шрифтов",
                Font = new Font("Segoe UI", 13.5f, FontStyle.Bold),
                ForeColor = Color.FromArgb(212, 175, 55),
                Location = new Point(20, 10),
                AutoSize = true
            };
            Label lblSub = new Label
            {
                Text = "Автономная установка инспектора Slate/UMG виджетов и сбор отчетов логов C7",
                Font = new Font("Segoe UI", 8.5f, FontStyle.Regular),
                ForeColor = Color.FromArgb(160, 170, 185),
                Location = new Point(22, 40),
                AutoSize = true
            };
            pnlHeader.Controls.Add(lblTitle);
            pnlHeader.Controls.Add(lblSub);
            this.Controls.Add(pnlHeader);

            // Path Selection
            Label lblPathTitle = new Label
            {
                Text = "Папка с клиентом игры (должна оканчиваться на Game\\C7):",
                Location = new Point(20, 82),
                AutoSize = true
            };
            this.Controls.Add(lblPathTitle);

            txtGamePath = new TextBox
            {
                Location = new Point(20, 106),
                Size = new Size(470, 26),
                BackColor = Color.FromArgb(32, 38, 48),
                ForeColor = Color.White,
                BorderStyle = BorderStyle.FixedSingle
            };
            txtGamePath.TextChanged += (s, e) => CheckCurrentStatus();
            this.Controls.Add(txtGamePath);

            btnBrowse = new Button
            {
                Text = "Обзор...",
                Location = new Point(500, 105),
                Size = new Size(90, 28),
                BackColor = Color.FromArgb(45, 52, 65),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat
            };
            btnBrowse.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 98);
            btnBrowse.Click += BtnBrowse_Click;
            this.Controls.Add(btnBrowse);

            btnAutoDetect = new Button
            {
                Text = "Автопоиск",
                Location = new Point(600, 105),
                Size = new Size(95, 28),
                BackColor = Color.FromArgb(45, 52, 65),
                ForeColor = Color.FromArgb(212, 175, 55),
                FlatStyle = FlatStyle.Flat
            };
            btnAutoDetect.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 98);
            btnAutoDetect.Click += (s, e) => { AutoDetectGamePath(); CheckCurrentStatus(); };
            this.Controls.Add(btnAutoDetect);

            // Status label
            lblStatus = new Label
            {
                Text = "Статус: Определение статуса...",
                Location = new Point(20, 142),
                Size = new Size(675, 24),
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                ForeColor = Color.LightGreen
            };
            this.Controls.Add(lblStatus);

            // Action Buttons
            btnInstall = new Button
            {
                Text = "📥 1. Установить диагностику в игру",
                Location = new Point(20, 172),
                Size = new Size(330, 38),
                BackColor = Color.FromArgb(35, 80, 55),
                ForeColor = Color.White,
                Font = new Font("Segoe UI", 10f, FontStyle.Bold),
                FlatStyle = FlatStyle.Flat
            };
            btnInstall.FlatAppearance.BorderColor = Color.FromArgb(50, 120, 80);
            btnInstall.Click += BtnInstall_Click;
            this.Controls.Add(btnInstall);

            btnCollect = new Button
            {
                Text = "🔍 2. Собрать отчет и проверить",
                Location = new Point(365, 172),
                Size = new Size(330, 38),
                BackColor = Color.FromArgb(40, 70, 110),
                ForeColor = Color.FromArgb(212, 175, 55),
                Font = new Font("Segoe UI", 10f, FontStyle.Bold),
                FlatStyle = FlatStyle.Flat
            };
            btnCollect.FlatAppearance.BorderColor = Color.FromArgb(60, 100, 150);
            btnCollect.Click += BtnCollect_Click;
            this.Controls.Add(btnCollect);

            btnUninstall = new Button
            {
                Text = "🗑️ Удалить диагностику",
                Location = new Point(20, 220),
                Size = new Size(215, 30),
                BackColor = Color.FromArgb(45, 50, 60),
                ForeColor = Color.FromArgb(200, 200, 200),
                FlatStyle = FlatStyle.Flat
            };
            btnUninstall.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 98);
            btnUninstall.Click += BtnUninstall_Click;
            this.Controls.Add(btnUninstall);

            btnCopyReport = new Button
            {
                Text = "📋 Скопировать сводку",
                Location = new Point(245, 220),
                Size = new Size(215, 30),
                BackColor = Color.FromArgb(45, 50, 60),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat
            };
            btnCopyReport.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 98);
            btnCopyReport.Click += BtnCopyReport_Click;
            this.Controls.Add(btnCopyReport);

            btnOpenLogs = new Button
            {
                Text = "📂 Открыть папку логов",
                Location = new Point(470, 220),
                Size = new Size(225, 30),
                BackColor = Color.FromArgb(45, 50, 60),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat
            };
            btnOpenLogs.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 98);
            btnOpenLogs.Click += BtnOpenLogs_Click;
            this.Controls.Add(btnOpenLogs);

            // Log Console
            Label lblLogTitle = new Label
            {
                Text = "Журнал работы и сводка диагностики:",
                Location = new Point(20, 260),
                AutoSize = true
            };
            this.Controls.Add(lblLogTitle);

            rtbLog = new RichTextBox
            {
                Location = new Point(20, 285),
                Size = new Size(675, 280),
                BackColor = Color.FromArgb(15, 18, 24),
                ForeColor = Color.FromArgb(200, 210, 225),
                Font = new Font("Consolas", 9f, FontStyle.Regular),
                ReadOnly = true,
                BorderStyle = BorderStyle.FixedSingle
            };
            this.Controls.Add(rtbLog);

            Log("Инструмент диагностики LOTM UI запущен.");
        }

        private void Log(string msg)
        {
            if (rtbLog.InvokeRequired)
            {
                rtbLog.Invoke(new Action(() => Log(msg)));
                return;
            }
            rtbLog.AppendText("[" + DateTime.Now.ToString("HH:mm:ss") + "] " + msg + "\n");
            rtbLog.SelectionStart = rtbLog.Text.Length;
            rtbLog.ScrollToCaret();
        }

        private void AutoDetectGamePath()
        {
            // 1. Running processes
            try
            {
                string[] procNames = { "C7-Win64-Shipping", "Lord of Mysteries", "GMZZLauncher" };
                foreach (var name in procNames)
                {
                    var procs = Process.GetProcessesByName(name);
                    foreach (var p in procs)
                    {
                        try
                        {
                            string exePath = p.MainModule.FileName;
                            if (!string.IsNullOrEmpty(exePath))
                            {
                                string dir = Path.GetDirectoryName(exePath);
                                string found = TryResolveC7(dir);
                                if (found != null)
                                {
                                    txtGamePath.Text = found;
                                    Log("Игра обнаружена через запущенный процесс: " + found);
                                    return;
                                }
                            }
                        }
                        catch { }
                    }
                }
            }
            catch { }

            // 2. Standard install candidates
            string[] candidates = new string[]
            {
                @"D:\Games\GMZZLauncher\Game\C7",
                @"C:\Games\GMZZLauncher\Game\C7",
                @"E:\Games\GMZZLauncher\Game\C7",
                @"F:\Games\GMZZLauncher\Game\C7",
                @"C:\Program Files\GMZZLauncher\Game\C7",
                @"D:\Program Files\GMZZLauncher\Game\C7",
                @"C:\Program Files (x86)\GMZZLauncher\Game\C7",
                @"D:\Program Files (x86)\GMZZLauncher\Game\C7",
                @"D:\Games\Lord of Mysteries\Game\C7",
                @"C:\Games\Lord of Mysteries\Game\C7",
                @"E:\Games\Lord of Mysteries\Game\C7",
            };

            foreach (var path in candidates)
            {
                if (IsValidGameFolder(path))
                {
                    txtGamePath.Text = path;
                    Log("Автоматически обнаружена игра: " + path);
                    return;
                }
            }

            Log("Не удалось автоматически найти клиент. Пожалуйста, укажите папку через 'Обзор...'");
        }

        private string TryResolveC7(string dir)
        {
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return null;
            if (IsValidGameFolder(dir)) return NormalizeC7Path(dir);

            string subC7 = Path.Combine(dir, "C7");
            if (IsValidGameFolder(subC7)) return subC7;

            string subGameC7 = Path.Combine(dir, "Game", "C7");
            if (IsValidGameFolder(subGameC7)) return subGameC7;

            DirectoryInfo parent = Directory.GetParent(dir);
            int count = 0;
            while (parent != null && count < 4)
            {
                if (IsValidGameFolder(parent.FullName)) return NormalizeC7Path(parent.FullName);
                string pSubGameC7 = Path.Combine(parent.FullName, "Game", "C7");
                if (IsValidGameFolder(pSubGameC7)) return pSubGameC7;
                string pSubC7 = Path.Combine(parent.FullName, "C7");
                if (IsValidGameFolder(pSubC7)) return pSubC7;

                parent = parent.Parent;
                count++;
            }
            return null;
        }

        private bool IsValidGameFolder(string path)
        {
            if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path)) return false;
            if (Directory.Exists(Path.Combine(path, "Binaries", "Win64"))) return true;
            if (Directory.Exists(Path.Combine(path, "Saved", "Logs"))) return true;
            if (Directory.Exists(Path.Combine(path, "Content", "Paks"))) return true;
            if (File.Exists(Path.Combine(path, "Content", "Paks", "pakchunk0-Windows.pak"))) return true;
            return false;
        }

        private string NormalizeC7Path(string path)
        {
            if (path.EndsWith("C7", StringComparison.OrdinalIgnoreCase)) return path;
            if (Directory.Exists(Path.Combine(path, "C7"))) return Path.Combine(path, "C7");
            if (Directory.Exists(Path.Combine(path, "Game", "C7"))) return Path.Combine(path, "Game", "C7");
            return path;
        }

        private void CheckCurrentStatus()
        {
            string path = txtGamePath.Text.Trim();
            if (!IsValidGameFolder(path))
            {
                lblStatus.Text = "Статус: Укажите корректную папку Game\\C7";
                lblStatus.ForeColor = Color.OrangeRed;
                btnInstall.Enabled = false;
                btnCollect.Enabled = false;
                btnUninstall.Enabled = false;
                return;
            }

            btnInstall.Enabled = true;
            btnCollect.Enabled = true;

            string modFile = Path.Combine(path, "Saved", "Mods", "lua", "mods", "cpdd_runtime_fixes", "LotmDiagnostics.lua");
            string diagJson = Path.Combine(path, "Saved", "Logs", "lotm_diagnostics.json");

            if (File.Exists(modFile))
            {
                if (File.Exists(diagJson))
                {
                    lblStatus.Text = "Статус: Мод АКТИВЕН. Данные диагностики в наличии (готовы к сбору)!";
                    lblStatus.ForeColor = Color.LightGreen;
                }
                else
                {
                    lblStatus.Text = "Статус: Мод УСТАНОВЛЕН в игре. Ожидание запуска игры и открытия окон.";
                    lblStatus.ForeColor = Color.Gold;
                }
                btnUninstall.Enabled = true;
            }
            else
            {
                lblStatus.Text = "Статус: Игра готова к установке модуля диагностики.";
                lblStatus.ForeColor = Color.White;
                btnUninstall.Enabled = false;
            }
        }

        private void BtnBrowse_Click(object sender, EventArgs e)
        {
            using (FolderBrowserDialog fbd = new FolderBrowserDialog())
            {
                fbd.Description = "Выберите папку с игрой Lord of Mysteries (Game\\C7):";
                fbd.ShowNewFolderButton = false;
                if (!string.IsNullOrEmpty(txtGamePath.Text) && Directory.Exists(txtGamePath.Text))
                    fbd.SelectedPath = txtGamePath.Text;

                if (fbd.ShowDialog() == DialogResult.OK)
                {
                    txtGamePath.Text = NormalizeC7Path(fbd.SelectedPath);
                }
            }
        }

        private void BtnInstall_Click(object sender, EventArgs e)
        {
            string gamePath = txtGamePath.Text.Trim();
            if (!IsValidGameFolder(gamePath))
            {
                MessageBox.Show("Укажите правильную папку с игрой!", "Ошибка", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            try
            {
                Log("--- Установка модуля диагностики в игру ---");
                string modsDir = Path.Combine(gamePath, "Saved", "Mods");
                string luaDir = Path.Combine(modsDir, "lua", "mods", "cpdd_runtime_fixes");
                if (!Directory.Exists(luaDir)) Directory.CreateDirectory(luaDir);

                // 1. Install LotmDiagnostics.lua in both mods/cpdd_runtime_fixes and Mods root
                string modTarget = Path.Combine(luaDir, "LotmDiagnostics.lua");
                byte[] modBytes = Convert.FromBase64String(EmbeddedModLuaBase64);
                File.WriteAllBytes(modTarget, modBytes);
                Log("[OK] Файл LotmDiagnostics.lua записан: " + modTarget);

                string modTargetRoot = Path.Combine(modsDir, "LotmDiagnostics.lua");
                try { File.WriteAllBytes(modTargetRoot, modBytes); } catch { }

                // 2. Register in manifest.lua
                string manifestPath = Path.Combine(modsDir, "manifest.lua");
                if (!File.Exists(manifestPath))
                {
                    string minManifest = "return {\r\n    Overrides = {},\r\n    Load = {\r\n        \"mods.cpdd_runtime_fixes.Init\",\r\n        \"mods.cpdd_runtime_fixes.LotmDiagnostics\",\r\n    },\r\n}\r\n";
                    File.WriteAllText(manifestPath, minManifest, Encoding.UTF8);
                    Log("[OK] Создан manifest.lua с регистрацией диагностики.");
                }
                else
                {
                    string manifestContent = File.ReadAllText(manifestPath, Encoding.UTF8);
                    if (!manifestContent.Contains("mods.cpdd_runtime_fixes.LotmDiagnostics"))
                    {
                        string bak = manifestPath + ".bak_diag";
                        if (!File.Exists(bak)) File.Copy(manifestPath, bak);

                        if (manifestContent.Contains("Load = {"))
                        {
                            manifestContent = manifestContent.Replace("Load = {", "Load = {\r\n        \"mods.cpdd_runtime_fixes.LotmDiagnostics\",");
                        }
                        else if (manifestContent.Contains("Load={"))
                        {
                            manifestContent = manifestContent.Replace("Load={", "Load={\r\n        \"mods.cpdd_runtime_fixes.LotmDiagnostics\",");
                        }
                        File.WriteAllText(manifestPath, manifestContent, Encoding.UTF8);
                        Log("[OK] Модуль добавлен в список Load файла manifest.lua.");
                    }
                    else
                    {
                        Log("[OK] Модуль уже зарегистрирован в manifest.lua.");
                    }
                }

                // 3. Inject safe hooks into Init.lua if exists
                string initPath = Path.Combine(luaDir, "Init.lua");
                if (File.Exists(initPath))
                {
                    string initContent = File.ReadAllText(initPath, Encoding.UTF8);
                    bool modified = false;

                    if (!initContent.Contains("LotmDiagnostics"))
                    {
                        string snippet = "\r\n    pcall(function()\r\n        local ok = pcall(require, \"mods.cpdd_runtime_fixes.LotmDiagnostics\")\r\n        if not ok then pcall(require, \"LotmDiagnostics\") end\r\n    end)\r\n";
                        if (initContent.Contains("return {"))
                        {
                            int idx = initContent.LastIndexOf("return {");
                            initContent = initContent.Insert(idx, snippet);
                            modified = true;
                        }
                    }

                    if (initContent.Contains("repairComponent(component)") && !initContent.Contains("LotmDiagnostics.InspectPanel"))
                    {
                        initContent = initContent.Replace("repairComponent(component)", "repairComponent(component)\r\n    if _G.LotmDiagnostics and type(_G.LotmDiagnostics.InspectPanel) == \"function\" then pcall(_G.LotmDiagnostics.InspectPanel, _G.LotmDiagnostics, component, reason) end");
                        modified = true;
                    }

                    if (modified)
                    {
                        File.WriteAllText(initPath, initContent, Encoding.UTF8);
                        Log("[OK] Безопасная интеграция инспектора встроена в Init.lua.");
                    }
                }

                Log("===============================================================");
                Log("✅ МОДУЛЬ ДИАГНОСТИКИ УСПЕШНО УСТАНОВЛЕН!");
                Log("Инструкция по фиксации состояния:");
                Log("1. Запустите игру и зайдите в мир персонажем.");
                Log("2. Откройте МАГАЗИН (пролистайте вкладки и карточки).");
                Log("3. Откройте ДОСКУ ЗАДАНИЙ и ЖУРНАЛ КВЕСТОВ.");
                Log("4. Откройте ИНВЕНТАРЬ и наведите на пару предметов.");
                Log("5. Вернитесь сюда и нажмите кнопку '🔍 2. Собрать отчет и проверить'.");
                Log("===============================================================");

                CheckCurrentStatus();
                MessageBox.Show("Модуль диагностики успешно установлен в игру!\n\nТеперь запустите игру, откройте Магазин и Квесты, затем нажмите кнопку 'Собрать отчет'.", "Установка завершена", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                Log("[ОШИБКА] Не удалось установить: " + ex.Message);
                MessageBox.Show("Ошибка при установке: " + ex.Message, "Ошибка", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private string lastGeneratedSummary = "";

        private void BtnCollect_Click(object sender, EventArgs e)
        {
            string gamePath = txtGamePath.Text.Trim();
            if (!IsValidGameFolder(gamePath))
            {
                MessageBox.Show("Укажите правильную папку с игрой!", "Ошибка", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            try
            {
                Log("--- Сбор логов и диагностического отчета ---");
                string logsDir = Path.Combine(gamePath, "Saved", "Logs");
                string reportPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "lotm_report.txt");

                StringBuilder sb = new StringBuilder();
                sb.AppendLine("================================================================================");
                sb.AppendLine(" LORD OF THE MYSTERIES — ИТОГОВЫЙ ДИАГНОСТИЧЕСКИЙ ОТЧЕТ");
                sb.AppendLine(" Сгенерировано: " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
                sb.AppendLine(" Папка игры:    " + gamePath);
                sb.AppendLine(" Папка логов:   " + logsDir);
                sb.AppendLine("================================================================================");
                sb.AppendLine();

                string diagJson = Path.Combine(logsDir, "lotm_diagnostics.json");
                if (!File.Exists(diagJson))
                {
                    string tempJson = Path.Combine(Path.GetTempPath(), "lotm_diagnostics.json");
                    if (File.Exists(tempJson)) diagJson = tempJson;
                }

                string diagTxt = Path.Combine(logsDir, "lotm_diagnostics.txt");
                if (!File.Exists(diagTxt))
                {
                    string tempTxt = Path.Combine(Path.GetTempPath(), "lotm_diagnostics.txt");
                    if (File.Exists(tempTxt)) diagTxt = tempTxt;
                }

                string errLog = Path.Combine(logsDir, "lotm_diagnostics_error.log");
                if (!File.Exists(errLog))
                {
                    string tempErr = Path.Combine(Path.GetTempPath(), "lotm_diagnostics_error.log");
                    if (File.Exists(tempErr)) errLog = tempErr;
                }

                if (File.Exists(errLog))
                {
                    Log("[!] Обнаружен журнал ошибок мода: " + errLog);
                    sb.AppendLine("--- ⚠️ ЖУРНАЛ ОШИБОК ДИАГНОСТИКИ ---");
                    sb.AppendLine(File.ReadAllText(errLog, Encoding.UTF8));
                    sb.AppendLine();
                }

                int panelsCount = 0;
                int widgetsCount = 0;
                List<string> activePanels = new List<string>();

                if (File.Exists(diagJson))
                {
                    Log("[OK] Обнаружен JSON файл диагностики: " + diagJson);
                    string json = File.ReadAllText(diagJson, Encoding.UTF8);

                    var panelMatches = Regex.Matches(json, "\"uid\":\\s*\"([^\"]+)\"");
                    foreach (Match m in panelMatches)
                    {
                        if (!activePanels.Contains(m.Groups[1].Value))
                            activePanels.Add(m.Groups[1].Value);
                    }
                    panelsCount = activePanels.Count;

                    var widgetMatches = Regex.Matches(json, "\"name\":\\s*\"([^\"]+)\"");
                    widgetsCount = widgetMatches.Count;

                    sb.AppendLine("--- 1. ДИАГНОСТИКА МОДА (JSON) ---");
                    sb.AppendLine("Захвачено панелей: " + panelsCount + " (" + string.Join(", ", activePanels.ToArray()) + ")");
                    sb.AppendLine("Всего проинспектировано виджетов: " + widgetsCount);
                    sb.AppendLine();
                    sb.AppendLine(json);
                    sb.AppendLine();
                }
                else
                {
                    Log("[!] Файл lotm_diagnostics.json пока не найден в Saved\\Logs или %TEMP%.");
                    sb.AppendLine("--- 1. ДИАГНОСТИКА МОДА (JSON) ---");
                    sb.AppendLine("lotm_diagnostics.json не найден.");
                    sb.AppendLine();
                }

                if (File.Exists(diagTxt))
                {
                    Log("[OK] Обнаружен текстовый отчет диагностики: " + diagTxt);
                    sb.AppendLine("--- 1.1 ТЕКСТОВАЯ СВОДКА ВИДЖЕТОВ ---");
                    sb.AppendLine(File.ReadAllText(diagTxt, Encoding.UTF8));
                    sb.AppendLine();
                }

                string c7Log = Path.Combine(logsDir, "C7.log");
                int slateWarnings = 0;
                int diagMessages = 0;
                if (File.Exists(c7Log))
                {
                    Log("[OK] Обнаружен главный лог игры: " + c7Log);
                    string[] lines = File.ReadAllLines(c7Log, Encoding.UTF8);
                    List<string> filtered = new List<string>();

                    foreach (var l in lines)
                    {
                        string lower = l.ToLowerInvariant();
                        if (l.Contains("[LotmDiagnostics]"))
                        {
                            diagMessages++;
                            filtered.Add(l);
                        }
                        else if (lower.Contains("logslate: warning") || lower.Contains("slate: warning") || (lower.Contains("slate") && lower.Contains("font")))
                        {
                            slateWarnings++;
                            filtered.Add(l);
                        }
                    }

                    sb.AppendLine("--- 2. КЛЮЧЕВЫЕ СООБЩЕНИЯ ДВИЖКА (SLATE & МОД) ---");
                    sb.AppendLine("Записей [LotmDiagnostics]: " + diagMessages);
                    sb.AppendLine("Предупреждений Slate/Font: " + slateWarnings);
                    sb.AppendLine();
                    foreach (var fl in filtered) sb.AppendLine(fl);
                    sb.AppendLine();

                    sb.AppendLine("--- 3. ПОСЛЕДНИЕ 300 СТРОК C7.LOG ---");
                    int start = Math.Max(0, lines.Length - 300);
                    for (int i = start; i < lines.Length; i++) sb.AppendLine(lines[i]);
                    sb.AppendLine();
                }

                File.WriteAllText(reportPath, sb.ToString(), Encoding.UTF8);
                Log("[OK] Итоговый отчет сохранен в: " + reportPath);

                // Summary for user
                StringBuilder summary = new StringBuilder();
                summary.AppendLine("=== РЕЗЮМЕ ДИАГНОСТИКИ UI & ШРИФТОВ ===");
                summary.AppendLine("• Статус данных: " + (File.Exists(diagJson) ? "УСПЕШНО ПОЛУЧЕНЫ" : "НЕТ ФАЙЛА (откройте Магазин в игре)"));
                summary.AppendLine("• Захваченные панели: " + panelsCount + " (" + string.Join(", ", activePanels.ToArray()) + ")");
                summary.AppendLine("• Проинспектировано текстовых виджетов: " + widgetsCount);
                summary.AppendLine("• Предупреждений Slate/Шрифтов в C7.log: " + slateWarnings);
                summary.AppendLine("• Сообщений инспектора в логе: " + diagMessages);
                summary.AppendLine("========================================");

                lastGeneratedSummary = summary.ToString();
                Log("\n" + lastGeneratedSummary);

                try
                {
                    Clipboard.SetText(lastGeneratedSummary + "\n" + (File.Exists(reportPath) ? File.ReadAllText(reportPath) : ""));
                    Log("📋 Сводка и отчет АВТОМАТИЧЕСКИ скопированы в буфер обмена Windows!");
                }
                catch { }

                try
                {
                    Process.Start("notepad.exe", reportPath);
                }
                catch { }

                CheckCurrentStatus();
                MessageBox.Show("Сбор диагностики завершен!\n\nОтчет скопирован в буфер обмена и открыт в Блокноте.\nВы можете вставить его в чат (Ctrl+V) или прикрепить файл lotm_report.txt.", "Готово", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                Log("[ОШИБКА] " + ex.Message);
                MessageBox.Show("Ошибка при сборе логов: " + ex.Message, "Ошибка", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void BtnUninstall_Click(object sender, EventArgs e)
        {
            string gamePath = txtGamePath.Text.Trim();
            if (!IsValidGameFolder(gamePath)) return;

            try
            {
                string modFile = Path.Combine(gamePath, "Saved", "Mods", "lua", "mods", "cpdd_runtime_fixes", "LotmDiagnostics.lua");
                if (File.Exists(modFile))
                {
                    File.Delete(modFile);
                    Log("[OK] Файл LotmDiagnostics.lua удален.");
                }

                string manifestPath = Path.Combine(gamePath, "Saved", "Mods", "manifest.lua");
                string bak = manifestPath + ".bak_diag";
                if (File.Exists(bak))
                {
                    File.Copy(bak, manifestPath, true);
                    File.Delete(bak);
                    Log("[OK] manifest.lua восстановлен из резервной копии.");
                }

                CheckCurrentStatus();
                Log("Модуль диагностики успешно удален из игры.");
                MessageBox.Show("Модуль диагностики успешно удален из игры.", "Удаление", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                Log("[ОШИБКА] " + ex.Message);
            }
        }

        private void BtnCopyReport_Click(object sender, EventArgs e)
        {
            try
            {
                string reportPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "lotm_report.txt");
                if (File.Exists(reportPath))
                {
                    Clipboard.SetText(File.ReadAllText(reportPath));
                    Log("📋 Полный отчет lotm_report.txt скопирован в буфер обмена!");
                    MessageBox.Show("Отчет скопирован в буфер обмена!", "Успех", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                else if (!string.IsNullOrEmpty(lastGeneratedSummary))
                {
                    Clipboard.SetText(lastGeneratedSummary);
                    Log("📋 Сводка скопирована в буфер обмена!");
                    MessageBox.Show("Сводка скопирована в буфер обмена!", "Успех", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                else
                {
                    MessageBox.Show("Сначала нажмите 'Собрать отчет и проверить'.", "Информация", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
            }
            catch (Exception ex)
            {
                Log("[ОШИБКА] " + ex.Message);
            }
        }

        private void BtnOpenLogs_Click(object sender, EventArgs e)
        {
            string gamePath = txtGamePath.Text.Trim();
            if (!IsValidGameFolder(gamePath)) return;

            string logsDir = Path.Combine(gamePath, "Saved", "Logs");
            if (!Directory.Exists(logsDir))
            {
                Directory.CreateDirectory(logsDir);
            }
            try
            {
                Process.Start("explorer.exe", logsDir);
            }
            catch { }
        }
    }
}
