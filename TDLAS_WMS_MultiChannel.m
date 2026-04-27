% =========================================================================
% TDLAS_WMS_MultiChannel.m
% TDLAS-WMS三信道信号解调程序
%
% 作者    : https://github.com/RomaneeeCon
% 版本    : V1.0
% 日期    : 2026-01-29
%
% 功能描述:
%   基于波长调制光谱技术(WMS-2f)的TDLAS三通道气体检测信号处理程序，支持CO₂(2kHz)、N₂O(3kHz)、CO(5kHz)三种气体同时解调与分析。
%
% 处理流程:
%   1. 信号分段检测与预处理
%   2. 头尾基线提取与DC值计算
%   3. 三信道锁相解调(2F提取+相位校正)
%   4. 特征值提取(MAX、leftMIN、rightMIN、2F幅值、AMP值)
%   5. 结果可视化与数据保存
%
% 输入:
%   - CSV/TXT文件(2列:时间+总电压 或 4列:时间+3通道)
%   - 用户输入测试类型和气体浓度(静态测试)
%
% 输出:
%   - 分析结果TXT文件
%   - MAT工作空间
%   - 6+可视化图表
%
% 依赖:
%   - MATLAB R2020b或更高版本
%   - Signal Processing Toolbox
%
% 使用示例:
%   >> TDLAS_WMS_MultiChannel
%
% 版本历史:
%   V1.0 (2026-01-29) - 初始版本
% =========================================================================

clc; clear; close all;

%% TDLAS-WMS 三信道数据处理程序
%================================================================================
% 功能: 基于波长调制光谱技术(WMS-2f)的TDLAS三通道气体检测信号处理
%       支持 CO₂(2kHz)、N₂O(3kHz)、CO(5kHz) 三种气体同时解调与分析
%
% 主要流程:
%   1. 信号分段检测与预处理
%   2. 头尾基线提取与DC值计算
%   3. 三信道锁相解调 (2F提取 + 相位校正)
%   4. 特征值提取 (MAX、leftMIN、rightMIN、2F幅值、AMP值)
%   5. 结果可视化与数据保存
%
% 输入: CSV/TXT文件 (2列: 时间+总电压 或 4列: 时间+3通道)
% 输出: 分析结果TXT文件、MAT工作空间、6+图表
%
% 更新日期: 2026-01-29
% 作者：https://github.com/RomaneeeCon
%================================================================================

%% 全局配置参数
CONFIG.THRESHOLD_HIGH = 0.10;       % 高阈值用于触发 (注：总信号幅度通常较大，阈值需相应调整)
CONFIG.THRESHOLD_LOW = 0.05;        % 低阈值用于重置
CONFIG.TARGET_DURATION = 0.16;     % 目标信号长度(秒)，对应驱动段时长
CONFIG.TOLERANCE = 0.01 * CONFIG.TARGET_DURATION; % 允许的误差范围(秒)
CONFIG.TRIM_START = 0.02;          % 去除前部的比例 (2%)
CONFIG.TRIM_END = 0.02;            % 去除后部的比例 (2%)

% 三信道配置 (气体类型、调制频率、谐波次数、颜色、相位校正目标时间、特征提取时间窗口)
% 1 CO₂ (新1号信道)
CHANNELS(1).NAME = 'CO2';          % 信道1：二氧化碳
CHANNELS(1).FREQ = 2000.0;         % 调制频率 2kHz
CHANNELS(1).HARMONIC = 2;          % 2F解调
CHANNELS(1).COLOR = [0.0 0.4 1.0]; % 蓝色系

CHANNELS(1).MAX_TARGET = 0.080;      % CO2 MAX 的目标时间
CHANNELS(1).LEFT_MIN_TARGET = 0.060; % CO2 leftMIN 的目标时间
CHANNELS(1).RIGHT_MIN_TARGET = 0.100;% CO2 rightMIN 的目标时间

CHANNELS(1).TARGET_TIME = 0.080;    % CO2 (2kHz) 相位校正目标时间

% 2 N₂O (原1号信道，现为2号)
CHANNELS(2).NAME = 'N2O';          % 信道2：氧化亚氮
CHANNELS(2).FREQ = 3010.0;         % 调制频率 3kHz
CHANNELS(2).HARMONIC = 2;          % 2F解调
CHANNELS(2).COLOR = [1.0 0.5 0.0]; % 橙色系

CHANNELS(2).MAX_TARGET = 0.097;      % N2O MAX 的目标时间
CHANNELS(2).LEFT_MIN_TARGET = 0.0788; % N2O leftMIN 的目标时间
CHANNELS(2).RIGHT_MIN_TARGET = 0.115;% N2O rightMIN 的目标时间

CHANNELS(2).TARGET_TIME = 0.097;    % N2O (3kHz) 相位校正目标时间

% 3 CO (原2号信道，现为3号)
CHANNELS(3).NAME = 'CO';           % 信道3：一氧化碳
CHANNELS(3).FREQ = 5017.5;         % 调制频率 5kHz
CHANNELS(3).HARMONIC = 2;          % 2F解调
CHANNELS(3).COLOR = [1.0 0.1 0.1]; % 红色系

CHANNELS(3).MAX_TARGET = 0.114;      % CO MAX 的目标时间
CHANNELS(3).LEFT_MIN_TARGET = 0.0967; % CO leftMIN 的目标时间
CHANNELS(3).RIGHT_MIN_TARGET = 0.132;% CO rightMIN 的目标时间

CHANNELS(3).TARGET_TIME = 0.114;    % CO  (5kHz) 相位校正目标时间

NUM_CHANNELS = length(CHANNELS);

% 锁相放大器配置 (各信道独立频率，但共享滤波器参数)
LOCKIN.PHASE_COMPENSATION = 0;     % 初始相位补偿 (度)
LOCKIN.FILTER_FP = 0.1;            % 低通滤波器通带 (Hz)
LOCKIN.FILTER_FSB = 120;           % 低通滤波器阻带 (Hz)

% 极值搜索窗口半径 (各信道共用)
FEATURE.SEARCH_WINDOW = 0.01;       % 极值搜索窗口半径 (s)

% DC提取配置: 定义头尾区间的相对位置 (百分比)
HEAD_START = 0.05;   % 头部开始位置: 5%
HEAD_END = 0.10;     % 头部结束位置: 10%
TAIL_START = 0.85;   % 尾部开始位置: 85%
TAIL_END = 0.90;     % 尾部结束位置: 90%

%% Part 1: 测试设置与数据导入
fprintf('=== TDLAS-WMS 三信道数据处理程序 ===\n');
fprintf('支持同时解调: CO₂(2kHz) | N₂O(3kHz) | CO(5kHz)\n\n');

fprintf('1 - 静态测试 (需要输入各气体浓度)\n');
fprintf('2 - 动态测试 (无需输入气体浓度)\n');
test_type = input('请选择测试类型 (1 或 2): ');

if test_type == 1
    is_static_test = true;
    fprintf('请输入各信道气体浓度 (ppm):\n');
    for ch = 1:NUM_CHANNELS
        CHANNELS(ch).CONCENTRATION = input(sprintf('  %s浓度: ', CHANNELS(ch).NAME));
        if isnan(CHANNELS(ch).CONCENTRATION)
            error('输入的浓度值无效！');
        end
    end
    fprintf('气体浓度设置完成。\n');
elseif test_type == 2
    is_static_test = false;
    for ch = 1:NUM_CHANNELS
        CHANNELS(ch).CONCENTRATION = NaN;
    end
    fprintf('动态测试模式，无需输入气体浓度\n');
else
    error('无效的测试类型选择，请输入 1 或 2。');
end

% 生成统一的时间戳，确保文件命名一致
global_timestamp = datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss');
timestamp_str = string(global_timestamp);

% 数据导入 - 支持两列(总信号)或四列(时间+3个独立信道)
[fileName, folderPath] = uigetfile({'*.TXT;*.txt', 'Text Files (*.TXT, *.txt)'; ...
    '*.*', 'All Files (*.*)'}, '选择数据文件');

if fileName == 0
    error('未选择文件，程序终止。');
end

filePath = fullfile(folderPath, fileName);
if ~isfile(filePath)
    error('文件不存在，请检查路径是否正确：%s', filePath);
end

% 获取文件扩展名，判断文件类型
[~, ~, fileExt] = fileparts(fileName);
fileExt = lower(fileExt);

% 根据文件类型选择不同的读取方式
if strcmp(fileExt, '.csv')
    BackGround_data = readmatrix(filePath, 'HeaderLines', 3);
    disp('CSV文件导入中，已跳过前3行头部信息...');
elseif strcmp(fileExt, '.txt')
    BackGround_data = readmatrix(filePath);
    disp('TXT文件导入中...');
else
    error('不支持的文件格式: %s，请选择TXT或CSV文件。', fileExt);
end

% 验证数据有效性
if isempty(BackGround_data) || size(BackGround_data, 1) < 2
    error('数据文件为空或数据行数不足，请检查文件内容。');
end

% 支持2列(时间+总信号)或4列(时间+3信道)
[num_samples, num_cols] = size(BackGround_data);
fprintf('检测到数据格式: %d 列, %d 行\n', num_cols, num_samples);

if num_cols == 2
    % 单探测器总信号模式：[时间, 总电压]
    time = BackGround_data(:, 1);          % 第一列为时间
    raw_total_signal = BackGround_data(:, 2); % 第二列为总信号幅值
    disp('检测到单探测器总信号格式（2列），将对同一信号分别进行2/3/5kHz锁相解调。');
elseif num_cols >= 4
    % 兼容模式：[时间, CH1, CH2, CH3]，但三信道实际为同一总信号
    time = BackGround_data(:, 1);
    raw_total_signal = BackGround_data(:, 2); % 使用第一信道作为总信号
    warning('检测到多列格式，将使用第一信道(CH1)作为总信号进行三信道解调。');
else
    error('数据文件需要2列（时间+总信号）或至少4列，当前只有%d列。', num_cols);
end

disp('信号导入完毕。');

%% Part 2: 信号预处理 (分段/对齐/清洗) 与信号头尾区间检查
% 采样频率计算
if length(time) < 2
    error('时间序列长度不足！');
end
fs = 1 / (time(2) - time(1));
disp(['采样频率为: ', num2str(fs), ' Hz']);

% 信号分段检测 (基于总信号包络)
max_segments = ceil(length(raw_total_signal) / (CONFIG.TARGET_DURATION * fs));
start_index = nan(max_segments, 1);
end_index = nan(max_segments, 1);
signal_segments = cell(max_segments, 1);
triggered = false;
segment_count = 0;

% 使用总信号进行脉冲检测，确保三信道片段对齐
for i = 1:length(raw_total_signal)
    if raw_total_signal(i) > CONFIG.THRESHOLD_HIGH && ~triggered
        triggered = true;
        segment_count = segment_count + 1;
        start_index(segment_count) = i;
    elseif raw_total_signal(i) < CONFIG.THRESHOLD_LOW && triggered
        triggered = false;
        end_index(segment_count) = i;
        signal_segments{segment_count} = raw_total_signal(start_index(segment_count):end_index(segment_count));
    end
end

% 修正片段有效性
valid_segments = isfinite(start_index(1:segment_count)) & isfinite(end_index(1:segment_count));
start_index = start_index(valid_segments);
end_index = end_index(valid_segments);
signal_segments = signal_segments(valid_segments);
segment_count = sum(valid_segments);

% 片段筛选 (基于时长)
filtered_signal_segments = {};
filtered_start_index = [];
filtered_end_index = [];
for i = 1:segment_count
    segment_time = time(start_index(i):end_index(i));
    segment_duration = segment_time(end) - segment_time(1);
    if abs(segment_duration - CONFIG.TARGET_DURATION) <= CONFIG.TOLERANCE
        filtered_signal_segments{end+1} = signal_segments{i};
        filtered_start_index = [filtered_start_index, start_index(i)];
        filtered_end_index = [filtered_end_index, end_index(i)];
    end
end
num_segments = length(filtered_signal_segments);
disp(['提取到 ', num2str(num_segments), ' 个有效片段。']);

if num_segments == 0
    error('未检测到有效信号片段，请检查阈值设置。');
end

% 对齐与截取 (针对总信号)
aligned_signal_segments = filtered_signal_segments;
% 计算平均高电平时间
high_level_durations = arrayfun(@(i) time(filtered_end_index(i)) - time(filtered_start_index(i)), 1:num_segments);
average_period = mean(high_level_durations);

trimmed_signal_segments = {};
trimmed_time_segments = {};
start_positions = []; end_positions = [];

for i = 1:num_segments
    segment_raw = aligned_signal_segments{i};
    seg_len = length(segment_raw);
    start_cut = floor(seg_len * CONFIG.TRIM_START);
    end_cut = floor(seg_len * CONFIG.TRIM_END);

    current_trimmed_sig = segment_raw(start_cut+1 : end-end_cut);
    % 构造临时相对时间轴用于存储
    current_trimmed_time = (0:length(current_trimmed_sig)-1) / fs;

    trimmed_signal_segments{end+1} = current_trimmed_sig;
    trimmed_time_segments{end+1} = current_trimmed_time;
end

min_cycle_length = min(cellfun(@length, trimmed_signal_segments));
actual_cleaned_duration = average_period * (1 - CONFIG.TRIM_START - CONFIG.TRIM_END);
new_time_axis = linspace(0, actual_cleaned_duration, min_cycle_length);

% 整理为矩阵 [num_segments x min_cycle_length]
% 这是总信号的清洗后矩阵，后续三信道解调均基于此
cleaned_signals_matrix = NaN(num_segments, min_cycle_length);
for i = 1:num_segments
    sig = trimmed_signal_segments{i};
    cleaned_signals_matrix(i, :) = sig(1:min_cycle_length);
end

% 绘图1: 原始信号与分段 (总信号)
figure('Name', '原始信号分段 (总信号)');
subplot(2, 1, 1);
plot(time, raw_total_signal, 'b'); hold on;
plot(time(filtered_start_index), raw_total_signal(filtered_start_index), 'go', 'MarkerSize', 8);
plot(time(filtered_end_index), raw_total_signal(filtered_end_index), 'ro', 'MarkerSize', 8);
title('原始总信号及触发点'); grid on;
subplot(2, 1, 2); hold on;
colors = lines(num_segments);
for i = 1:num_segments
    segment_time = time(filtered_start_index(i):filtered_end_index(i));
    plot(segment_time, raw_total_signal(filtered_start_index(i):filtered_end_index(i)), 'Color', colors(i, :));
end
title('提取的信号片段 (总信号)'); grid on;


% 功能: 检查总信号段头部和尾部的波形特征，用于评估基线稳定性

fprintf('\n=== 信号头尾区间检查 ===\n');
fprintf('头部区间: %.0f%% - %.0f%%\n', HEAD_START*100, HEAD_END*100);
fprintf('尾部区间: %.0f%% - %.0f%%\n', TAIL_START*100, TAIL_END*100);

% 创建图形窗口
figure('Name', '信号头尾区间检查 (总信号)');
hold on;
colors = lines(num_segments);
% 绘制所有完整信号
for i = 1:num_segments
    plot(new_time_axis, cleaned_signals_matrix(i, :), 'Color', colors(i, :), 'LineWidth', 1.2);
end

% 计算头尾区间边界时间
seg_length = length(new_time_axis);
head_start_time = new_time_axis(round(seg_length * HEAD_START));
head_end_time = new_time_axis(round(seg_length * HEAD_END));
tail_start_time = new_time_axis(round(seg_length * TAIL_START));
tail_end_time = new_time_axis(round(seg_length * TAIL_END));

% 绘制垂直标记线（蓝色:头部，红色:尾部）
y_limits = get(gca, 'YLim');
plot([head_start_time, head_start_time], y_limits, 'b--', 'LineWidth', 1.5);
plot([head_end_time, head_end_time], y_limits, 'b--', 'LineWidth', 1.5);
plot([tail_start_time, tail_start_time], y_limits, 'r--', 'LineWidth', 1.5);
plot([tail_end_time, tail_end_time], y_limits, 'r--', 'LineWidth', 1.5);

title(sprintf('总信号头尾区间检查 (蓝色:头部, 红色:尾部)'));
xlabel('时间 (s)');
ylabel('信号幅值');
grid on;
box on;
hold off;
fprintf('头尾区间检查图形绘制完成。\n');

%%  Part 3: 头尾信号基线提取与低通滤波分析
% 功能：从总信号头尾高频振荡信号中提取**毫秒级基线漂移趋势**
% 滤波目标：强力抑制 2/3/5 kHz+ 载波，同时完整保留 100–500 Hz 基线动态
% 推荐参数：fc = 800 Hz，4阶 Butterworth + filtfilt

fprintf('\n=== 头尾信号基线趋势提取 (800 Hz 低通) ===\n');

% ---------------------- 滤波器参数 ----------------------
fc_lowpass = 800;    % 截止频率 800 Hz
order_butter = 4;    % 4阶 Butterworth
% ----------------------------------------------------------------

% 自动计算采样率（使用 new_time_axis）
if length(new_time_axis) < 2
    error('new_time_axis 长度不足，无法计算采样率');
end
dt = mean(diff(new_time_axis));
fs_actual = 1 / dt;

% 设计滤波器
wn = fc_lowpass / (fs_actual/2);
if wn >= 0.98, warning('警告：fc接近奈奎斯特频率'); end
if wn >= 1, error('fc超出奈奎斯特极限！'); end
[b, a] = butter(order_butter, wn, 'low');

% ---------------------- 提取头尾信号 ----------------------
head_raw_all = cell(num_segments, 1);
head_filt_all = cell(num_segments, 1);
tail_raw_all = cell(num_segments, 1);
tail_filt_all = cell(num_segments, 1);

for i = 1:num_segments
    signal = cleaned_signals_matrix(i, :);
    seg_len = length(signal);

    % 鲁棒索引（floor/ceil + 边界钳位）
    head_start_idx = max(1, floor(seg_len * HEAD_START) + 1);
    head_end_idx   = min(seg_len, ceil(seg_len * HEAD_END));
    tail_start_idx = max(1, floor(seg_len * TAIL_START) + 1);
    tail_end_idx   = min(seg_len, ceil(seg_len * TAIL_END));

    if head_start_idx >= head_end_idx || tail_start_idx >= tail_end_idx
        warning('信号段 %d 头尾区间无效，跳过。', i);
        head_raw_all{i} = []; head_filt_all{i} = [];
        tail_raw_all{i} = []; tail_filt_all{i} = [];
        continue;
    end

    % 提取头尾
    head_raw = signal(head_start_idx:head_end_idx);
    tail_raw = signal(tail_start_idx:tail_end_idx);

    % 零相位滤波
    head_filt = filtfilt(b, a, head_raw);
    tail_filt = filtfilt(b, a, tail_raw);

    head_raw_all{i} = head_raw;
    head_filt_all{i} = head_filt;
    tail_raw_all{i} = tail_raw;
    tail_filt_all{i} = tail_filt;
end

% ---------------------- 可视化 ----------------------
figure('Name', '头尾基线趋势提取 (总信号)');
sgtitle(sprintf('基线趋势提取 | fc=%.0f Hz, %d阶 Butterworth', fc_lowpass, order_butter), ...
    'FontSize', 12, 'FontWeight', 'bold');

subplot(1, 2, 1);
hold on;
colors = lines(num_segments);
for i = 1:num_segments
    if ~isempty(head_filt_all{i})
        plot(head_filt_all{i}, 'Color', colors(i,:), 'LineWidth', 2.0);
    end
end
% 添加30%-70%区间标记（绿色虚线+半透明高亮）
if ~isempty(head_filt_all{1})
    head_len = length(head_filt_all{1});
    % 画垂直虚线标记边界
    xline(head_len*0.3, 'g--', '30%', 'LineWidth', 1.5, 'LabelVerticalAlignment', 'bottom');
    xline(head_len*0.7, 'g--', '70%', 'LineWidth', 1.5, 'LabelVerticalAlignment', 'bottom');
end
title('头部信号 (滤波后)');
xlabel('采样点'); ylabel('幅值');
grid on; box on;

subplot(1, 2, 2);
hold on;
for i = 1:num_segments
    if ~isempty(tail_filt_all{i})
        plot(tail_filt_all{i}, 'Color', colors(i,:), 'LineWidth', 2.0);
    end
end
% 添加30%-70%区间标记
if ~isempty(tail_filt_all{1})
    tail_len = length(tail_filt_all{1});
    xline(tail_len*0.3, 'g--', '30%', 'LineWidth', 1.5, 'LabelVerticalAlignment', 'bottom');
    xline(tail_len*0.7, 'g--', '70%', 'LineWidth', 1.5, 'LabelVerticalAlignment', 'bottom');
end
title('尾部信号 (滤波后)');
xlabel('采样点'); ylabel('幅值');
grid on; box on;

% ---------------------- DC值提取 ----------------------
% 基于滤波后信号的 30%–70% 区间，稳健估计 DC 值
head_DC_values = NaN(num_segments, 1);
tail_DC_values = NaN(num_segments, 1);

for i = 1:num_segments
    if ~isempty(head_filt_all{i}) && ~isempty(tail_filt_all{i})
        % 头部 DC (30%-70%区间)
        head_len = length(head_filt_all{i});
        head_start_idx = max(1, round(head_len * 0.30) + 1);
        head_end_idx   = min(head_len, round(head_len * 0.70));
        head_DC_values(i) = mean(head_filt_all{i}(head_start_idx:head_end_idx));

        % 尾部 DC (30%-70%区间)
        tail_len = length(tail_filt_all{i});
        tail_start_idx = max(1, round(tail_len * 0.30) + 1);
        tail_end_idx   = min(tail_len, round(tail_len * 0.70));
        tail_DC_values(i) = mean(tail_filt_all{i}(tail_start_idx:tail_end_idx));
    else
        warning('信号段 %d 头尾滤波数据无效，DC值设为 NaN', i);
    end
end

% 计算最终 DC 值 (头部和尾部的平均值)
Final_DC_values = (head_DC_values + tail_DC_values) / 2;

% DC 值可视化
figure('Name', '直流分量（DC）提取结果');
sgtitle('总信号的直流分量（DC）估计', 'FontSize', 12, 'FontWeight', 'bold');

subplot(3, 1, 1);
plot(1:num_segments, head_DC_values, 'bo-', 'LineWidth', 1.5, 'MarkerFaceColor', 'b');
hold on; yline(mean(head_DC_values, 'omitnan'), 'r--', 'LineWidth', 2);
title('头部 DC 值'); xlabel('信号段索引'); ylabel('DC 幅值'); grid on;

subplot(3, 1, 2);
plot(1:num_segments, tail_DC_values, 'ro-', 'LineWidth', 1.5, 'MarkerFaceColor', 'r');
hold on; yline(mean(tail_DC_values, 'omitnan'), 'm--', 'LineWidth', 2);
title('尾部 DC 值'); xlabel('信号段索引'); ylabel('DC 幅值'); grid on;

subplot(3, 1, 3);
plot(1:num_segments, Final_DC_values, 'go-', 'LineWidth', 1.5, 'MarkerFaceColor', 'g');
hold on; yline(mean(Final_DC_values, 'omitnan'), 'k--', 'LineWidth', 2);
title('最终 DC 值 (头尾平均)'); xlabel('信号段索引'); ylabel('DC 幅值'); grid on;

% 统计摘要
fprintf('\nDC 值统计摘要:\n');
fprintf('  头部 DC 均值: %.6f ± %.6f (σ)\n', mean(head_DC_values, 'omitnan'), std(head_DC_values, 'omitnan'));
fprintf('  尾部 DC 均值: %.6f ± %.6f (σ)\n', mean(tail_DC_values, 'omitnan'), std(tail_DC_values, 'omitnan'));
fprintf('  最终 DC 均值: %.6f ± %.6f (σ)\n', mean(Final_DC_values, 'omitnan'), std(Final_DC_values, 'omitnan'));

%% Part 4: 三信道锁相解调 (2F提取)
fprintf('\n=== 开始三信道锁相解调 ===\n');

% 共用FIR滤波器设计 (Kaiser窗，基于配置参数)
[N_fir, ~, beta, ~] = kaiserord([LOCKIN.FILTER_FP, LOCKIN.FILTER_FSB], [1, 0], [0.0001, 0.01], fs);
N_fir = N_fir + mod(N_fir, 2);
fir_coeff = single(fir1(N_fir, LOCKIN.FILTER_FP/(fs/2), kaiser(N_fir+1, beta), 'low'));
fprintf('FIR滤波器阶数: %d，通带: %.0f Hz，阻带: %.0f Hz\n', N_fir, LOCKIN.FILTER_FP, LOCKIN.FILTER_FSB);

% 降采样参数设置
target_points = 500;
time_axis_sampled = linspace(0, actual_cleaned_duration, target_points);

% 对每个信道进行独立解调
for ch = 1:NUM_CHANNELS
    fprintf('\n正在解调 %s 信道 (%.1f kHz, 2F=%.1f kHz)...\n', ...
        CHANNELS(ch).NAME, CHANNELS(ch).FREQ/1000, 2*CHANNELS(ch).FREQ/1000);

    freq = CHANNELS(ch).FREQ;           % 当前信道调制频率
    harmonic = CHANNELS(ch).HARMONIC;   % =2 (2F解调)

    % 预分配第一次解调结果
    I_demod = zeros(num_segments, min_cycle_length);
    Q_demod = zeros(num_segments, min_cycle_length);
    amplitude = zeros(num_segments, min_cycle_length);
    phase_deg = zeros(num_segments, min_cycle_length);

    % 生成第一次解调参考信号 (初始相位0)
    ref_arg = 2 * pi * harmonic * freq * new_time_axis;
    ref_cos = cos(ref_arg);
    ref_sin = sin(ref_arg);

    % 第一次解调：获取粗相位和幅值
    for i = 1:num_segments
        signal = cleaned_signals_matrix(i, :);  % 总信号片段
        I_demod(i, :) = filter(fir_coeff, 1, signal .* ref_cos);
        Q_demod(i, :) = filter(fir_coeff, 1, signal .* ref_sin);
        amplitude(i, :) = 2 * sqrt(I_demod(i, :).^2 + Q_demod(i, :).^2);
        phase_deg(i, :) = rad2deg(atan2(Q_demod(i, :), I_demod(i, :)));
    end

    % 使用各信道独立的相位校正目标时间
    current_target_time = CHANNELS(ch).TARGET_TIME;
    corr_window_start = current_target_time * 0.8;  % 当前信道的校正窗口开始
    corr_window_end   = current_target_time * 1.2;  % 当前信道的校正窗口结束

    window_mask = (new_time_axis >= corr_window_start) & (new_time_axis <= corr_window_end);
    window_idx = find(window_mask);

    if isempty(window_idx)
        error('%s 信道的相位校正窗口为空，请检查 TARGET_TIME (%.3fs) 和 new_time_axis 范围', ...
            CHANNELS(ch).NAME, current_target_time);
    end

    % 预分配校正后结果
    I_demod_corr = zeros(num_segments, min_cycle_length);
    Q_demod_corr = zeros(num_segments, min_cycle_length);
    amplitude_corr = zeros(num_segments, min_cycle_length);
    phase_deg_corr = zeros(num_segments, min_cycle_length);

    % 第二次解调：基于第一次结果进行相位校正
    for i = 1:num_segments
        % 在窗口内找最大幅值点，计算需要校正的相位角
        [~, rel_idx] = max(amplitude(i, window_idx));
        max_idx = window_idx(rel_idx);
        correction_angle = deg2rad(phase_deg(i, max_idx));

        % 生成相位校正后的参考信号（使用当前信道的实际目标时间）
        ref_arg_corr = 2 * pi * harmonic * freq * new_time_axis - correction_angle;

        % 第二次锁相解调
        I_demod_corr(i, :) = filter(fir_coeff, 1, cleaned_signals_matrix(i, :) .* cos(ref_arg_corr));
        Q_demod_corr(i, :) = filter(fir_coeff, 1, cleaned_signals_matrix(i, :) .* sin(ref_arg_corr));

        % 计算校正后的幅值
        amplitude_corr(i, :) = 2 * sqrt(I_demod_corr(i, :).^2 + Q_demod_corr(i, :).^2);

        % 计算并校正相位翻转（使用当前信道的窗口）
        phase_rad = atan2(Q_demod_corr(i, :), I_demod_corr(i, :));
        [~, rel_idx_corr] = max(amplitude_corr(i, window_idx));
        max_idx_corr = window_idx(rel_idx_corr);

        if abs(rad2deg(phase_rad(max_idx_corr))) > 150
            phase_rad = phase_rad + pi;  % 相位翻转180度
        end
        phase_deg_corr(i, :) = rad2deg(phase_rad);
    end

    % 降采样存储到结构体 (供后续特征提取使用)
    CHANNELS(ch).I_DEMOD = zeros(num_segments, target_points, 'single');
    CHANNELS(ch).Q_DEMOD = zeros(num_segments, target_points, 'single');
    CHANNELS(ch).AMPLITUDE = zeros(num_segments, target_points, 'single');
    CHANNELS(ch).PHASE = zeros(num_segments, target_points, 'single');

    for i = 1:num_segments
        CHANNELS(ch).I_DEMOD(i, :) = single(interp1(new_time_axis, I_demod_corr(i, :), time_axis_sampled, 'linear'));
        CHANNELS(ch).Q_DEMOD(i, :) = single(interp1(new_time_axis, Q_demod_corr(i, :), time_axis_sampled, 'linear'));
        CHANNELS(ch).AMPLITUDE(i, :) = single(interp1(new_time_axis, amplitude_corr(i, :), time_axis_sampled, 'linear'));
        CHANNELS(ch).PHASE(i, :) = single(interp1(new_time_axis, phase_deg_corr(i, :), time_axis_sampled, 'linear'));
    end

    fprintf('  %s 信道: 完成相位校正与降采样 (500 points)\n', CHANNELS(ch).NAME);
end

%% Part 5: 三信道解调结果可视化
% 创建图形窗口
figure('Name', '三信道锁相解调结果 (2F信号)');

for ch = 1:NUM_CHANNELS
    row_offset = (ch-1) * 4;  % 每信道4个子图

    % 获取当前信道的相位校正窗口信息
    current_target_time = CHANNELS(ch).TARGET_TIME;
    corr_window_start = current_target_time * 0.8;
    corr_window_end   = current_target_time * 1.2;

    % 将窗口时间转换为降采样后的坐标索引（用于绘图）
    window_start_idx = round(corr_window_start / actual_cleaned_duration * (target_points - 1)) + 1;
    window_end_idx   = round(corr_window_end / actual_cleaned_duration * (target_points - 1)) + 1;
    % 限制索引范围
    window_start_idx = max(1, min(target_points, window_start_idx));
    window_end_idx   = max(1, min(target_points, window_end_idx));

    % I分量
    subplot(NUM_CHANNELS, 4, row_offset + 1);
    plot(time_axis_sampled, CHANNELS(ch).I_DEMOD', 'Color', CHANNELS(ch).COLOR, 'LineWidth', 1);
    hold on;
    % 绘制相位校正窗口边界线
    y_limits = get(gca, 'YLim');
    plot([corr_window_start, corr_window_start], y_limits, 'k--', 'LineWidth', 1.5);
    plot([corr_window_end, corr_window_end], y_limits, 'k--', 'LineWidth', 1.5);
    hold off;
    title(sprintf('%s (%.0fkHz): I分量', CHANNELS(ch).NAME, CHANNELS(ch).FREQ/1000));
    xlabel('时间 (s)'); ylabel('幅值'); grid on;

    % Q分量
    subplot(NUM_CHANNELS, 4, row_offset + 2);
    plot(time_axis_sampled, CHANNELS(ch).Q_DEMOD', 'Color', CHANNELS(ch).COLOR, 'LineWidth', 1);
    hold on;
    y_limits = get(gca, 'YLim');
    plot([corr_window_start, corr_window_start], y_limits, 'k--', 'LineWidth', 1.5);
    plot([corr_window_end, corr_window_end], y_limits, 'k--', 'LineWidth', 1.5);
    fill([corr_window_start, corr_window_end, corr_window_end, corr_window_start], ...
        [y_limits(1), y_limits(1), y_limits(2), y_limits(2)], ...
        [1 1 0], 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    hold off;
    title(sprintf('%s: Q分量', CHANNELS(ch).NAME));
    xlabel('时间 (s)'); ylabel('幅值'); grid on;

    % 幅值
    subplot(NUM_CHANNELS, 4, row_offset + 3);
    plot(time_axis_sampled, CHANNELS(ch).AMPLITUDE', 'Color', CHANNELS(ch).COLOR, 'LineWidth', 1);
    hold on;
    y_limits = get(gca, 'YLim');
    plot([corr_window_start, corr_window_start], y_limits, 'k--', 'LineWidth', 1.5);
    plot([corr_window_end, corr_window_end], y_limits, 'k--', 'LineWidth', 1.5);
    fill([corr_window_start, corr_window_end, corr_window_end, corr_window_start], ...
        [y_limits(1), y_limits(1), y_limits(2), y_limits(2)], ...
        [1 1 0], 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    hold off;
    title(sprintf('%s: 幅值', CHANNELS(ch).NAME));
    xlabel('时间 (s)'); ylabel('幅值'); grid on;

    % 相位
    subplot(NUM_CHANNELS, 4, row_offset + 4);
    plot(time_axis_sampled, CHANNELS(ch).PHASE', 'Color', CHANNELS(ch).COLOR, 'LineWidth', 1);
    hold on;
    y_limits = get(gca, 'YLim');
    plot([corr_window_start, corr_window_start], y_limits, 'k--', 'LineWidth', 1.5);
    plot([corr_window_end, corr_window_end], y_limits, 'k--', 'LineWidth', 1.5);
    fill([corr_window_start, corr_window_end, corr_window_end, corr_window_start], ...
        [y_limits(1), y_limits(1), y_limits(2), y_limits(2)], ...
        [1 1 0], 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    hold off;
    title(sprintf('%s: 相位', CHANNELS(ch).NAME));
    xlabel('时间 (s)'); ylabel('相位 (°)'); grid on;
end

% 添加总标题和图例说明
sgtitle(sprintf('三信道锁相解调结果 (降采样至%d点)', target_points), ...
    'FontSize', 14, 'FontWeight', 'bold');

% 打印各信道的校正窗口信息
fprintf('\n=== 各信道相位校正窗口信息 ===\n');
for ch = 1:NUM_CHANNELS
    fprintf('%s 信道: TARGET_TIME = %.3f s, 校正窗口 = [%.4f, %.4f] s\n', ...
        CHANNELS(ch).NAME, CHANNELS(ch).TARGET_TIME, ...
        CHANNELS(ch).TARGET_TIME * 0.8, CHANNELS(ch).TARGET_TIME * 1.2);
end

fprintf('\n三信道锁相解调可视化完成\n');

%% Part 6: 三信道特征值提取与2F幅值分析
fprintf('\n=== 开始三信道特征值提取与2F幅值分析 ===\n');

% 预分配三信道结果矩阵
secondHarmonic_all = NaN(NUM_CHANNELS, num_segments);  % 2F幅值 (Second Harmonic)
AMP_all = NaN(NUM_CHANNELS, num_segments);            % AMP值 (归一化幅值)
MAX_all = NaN(NUM_CHANNELS, num_segments);            % MAX极值
leftMIN_all = NaN(NUM_CHANNELS, num_segments);        % 左极小值
rightMIN_all = NaN(NUM_CHANNELS, num_segments);       % 右极小值

% 逐一处理各信道
for ch = 1:NUM_CHANNELS
    fprintf('\n正在提取 %s 信道特征值...\n', CHANNELS(ch).NAME);

    % ========== 获取当前信道的特征提取参数 ==========
    max_target = CHANNELS(ch).MAX_TARGET;        % MAX 的目标时间
    left_min_target = CHANNELS(ch).LEFT_MIN_TARGET;  % leftMIN 的目标时间
    right_min_target = CHANNELS(ch).RIGHT_MIN_TARGET;% rightMIN 的目标时间
    search_window = FEATURE.SEARCH_WINDOW;       % 搜索窗口半径

    % ========== 提取当前信道的解调结果 ==========
    % CHANNELS(ch).I_DEMOD 维度: [num_segments x target_points]
    I_data = CHANNELS(ch).I_DEMOD;

    % 转换为列向量用于搜索
    time_axis_col = time_axis_sampled';  % [target_points x 1]

    % 预分配当前信道的特征值结果
    MAX_values = NaN(num_segments, 1);
    leftMIN_values = NaN(num_segments, 1);
    rightMIN_values = NaN(num_segments, 1);

    % ========== 逐段提取特征值 ==========
    for i = 1:num_segments
        current_signal = I_data(i, :)';  % 当前信号段, 转为列向量

        % ---- 1. 查找 MAX (最大值) ----
        t_start = max_target - search_window;
        t_end   = max_target + search_window;
        mask = (time_axis_col >= t_start) & (time_axis_col <= t_end);
        if any(mask)
            [val, idx_in_mask] = max(current_signal(mask));
            idx_global = find(mask);
            MAX_values(i) = val;
        else
            warning('信号段 %d 在 MAX 搜索窗口内无有效数据', i);
        end

        % ---- 2. 查找 leftMIN (左极小值) ----
        t_start = left_min_target - search_window;
        t_end   = left_min_target + search_window;
        mask = (time_axis_col >= t_start) & (time_axis_col <= t_end);
        if any(mask)
            [val, idx_in_mask] = min(current_signal(mask));
            idx_global = find(mask);
            leftMIN_values(i) = val;
        else
            warning('信号段 %d 在 leftMIN 搜索窗口内无有效数据', i);
        end

        % ---- 3. 查找 rightMIN (右极小值) ----
        t_start = right_min_target - search_window;
        t_end   = right_min_target + search_window;
        mask = (time_axis_col >= t_start) & (time_axis_col <= t_end);
        if any(mask)
            [val, idx_in_mask] = min(current_signal(mask));
            idx_global = find(mask);
            rightMIN_values(i) = val;
        else
            warning('信号段 %d 在 rightMIN 搜索窗口内无有效数据', i);
        end
    end

    % ========== 计算2F幅值 ==========
    % 计算公式: 2F = MAX - (leftMIN + rightMIN) / 2
    secondHarmonic_values = MAX_values - (leftMIN_values + rightMIN_values) / 2;

    % ========== 计算AMP值 (归一化幅值) ==========
    % AMP = 2F / DC (使用Final_DC_values进行归一化)
    AMP_values = secondHarmonic_values ./ Final_DC_values;

    % ========== 存储结果到结构体 ==========
    CHANNELS(ch).MAX_VALUES = MAX_values;
    CHANNELS(ch).LEFTMIN_VALUES = leftMIN_values;
    CHANNELS(ch).RIGHTMIN_VALUES = rightMIN_values;
    CHANNELS(ch).SECOND_HARMONIC = secondHarmonic_values;
    CHANNELS(ch).AMP_VALUES = AMP_values;

    % ========== 存储到汇总矩阵 ==========
    secondHarmonic_all(ch, :) = secondHarmonic_values';
    AMP_all(ch, :) = AMP_values';
    MAX_all(ch, :) = MAX_values';
    leftMIN_all(ch, :) = leftMIN_values';
    rightMIN_all(ch, :) = rightMIN_values';

    % ========== 打印当前信道统计信息 ==========
    fprintf('  %s 信道特征值统计:\n', CHANNELS(ch).NAME);
    fprintf('    MAX 值:        %.6f ± %.6f\n', mean(MAX_values, 'omitnan'), std(MAX_values, 'omitnan'));
    fprintf('    leftMIN 值:    %.6f ± %.6f\n', mean(leftMIN_values, 'omitnan'), std(leftMIN_values, 'omitnan'));
    fprintf('    rightMIN 值:   %.6f ± %.6f\n', mean(rightMIN_values, 'omitnan'), std(rightMIN_values, 'omitnan'));
    fprintf('    2F 幅值:       %.6f ± %.6f\n', mean(secondHarmonic_values, 'omitnan'), std(secondHarmonic_values, 'omitnan'));
    fprintf('    AMP 值:        %.6f ± %.6f\n', mean(AMP_values, 'omitnan'), std(AMP_values, 'omitnan'));
end

% ====================== 汇总统计 ======================
fprintf('\n=== 三信道特征值汇总统计 ===\n');

% 创建汇总表格
feature_summary = table();
for ch = 1:NUM_CHANNELS
    % 创建当前信道的子表格
    n_seg = num_segments;
    gas_names = repmat({CHANNELS(ch).NAME}, n_seg, 1);
    seg_ids = (1:n_seg)';

    % 合并数据
    sub_table = table(gas_names, seg_ids, ...
        Final_DC_values, ...
        MAX_all(ch, :)', ...
        leftMIN_all(ch, :)', ...
        rightMIN_all(ch, :)', ...
        secondHarmonic_all(ch, :)', ...
        AMP_all(ch, :)', ...
        'VariableNames', {'Gas', 'Segment', 'DC_Value', 'MAX', 'leftMIN', 'rightMIN', 'SecondHarmonic', 'AMP'});

    if ch == 1
        feature_summary = sub_table;
    else
        feature_summary = [feature_summary; sub_table];
    end
end

% 显示汇总表格
disp('三信道特征值汇总表:');
disp(feature_summary);

% 打印各信道对比统计
fprintf('\n各信道2F幅值对比:\n');
fprintf('----------------------------------------\n');
fprintf('信道\t\t2F幅值均值\t\t2F幅值标准差\tAMP均值\t\tAMP标准差\n');
fprintf('----------------------------------------\n');
for ch = 1:NUM_CHANNELS
    fprintf('%s\t\t%.6f\t\t%.6f\t\t%.6f\t%.6f\n', ...
        CHANNELS(ch).NAME, ...
        mean(secondHarmonic_all(ch, :), 'omitnan'), ...
        std(secondHarmonic_all(ch, :), 'omitnan'), ...
        mean(AMP_all(ch, :), 'omitnan'), ...
        std(AMP_all(ch, :), 'omitnan'));
end
fprintf('----------------------------------------\n');

%% Part 6.1: 三信道2F信号特征点提取可视化
fprintf('\n=== 生成三信道2F信号特征点提取可视化 ===\n');

% 限制绘制数量的阈值
max_plot_segments = 10;

% 创建图形窗口
figure('Name', '三信道2F信号特征点提取');

% 确定每个信道实际绘制的段数
actual_plot_segments = min(num_segments, max_plot_segments);

% 随机种子设置（确保可重复性）
rng(42);

% 为每个信道随机选择要绘制的段索引
if num_segments <= max_plot_segments
    plot_indices = 1:num_segments;
else
    plot_indices = randperm(num_segments, max_plot_segments);
end

for ch = 1:NUM_CHANNELS
    subplot(NUM_CHANNELS, 1, ch);
    hold on;

    % 生成颜色映射
    colors_sub = lines(length(plot_indices));

    % 绘制选中的信号段
    for idx = 1:length(plot_indices)
        i = plot_indices(idx);
        plot(time_axis_sampled, CHANNELS(ch).I_DEMOD(i, :), ...
            'Color', colors_sub(idx, :), 'LineWidth', 1.0);

        % 标记特征点（如果有有效值）
        if i <= length(CHANNELS(ch).MAX_VALUES) && ~isnan(CHANNELS(ch).MAX_VALUES(i))
            % MAX点 - 上三角标记
            scatter(CHANNELS(ch).MAX_TARGET, CHANNELS(ch).MAX_VALUES(i), ...
                60, colors_sub(idx, :), 'filled', '^', ...
                'MarkerEdgeColor', 'k', 'LineWidth', 1);
        end

        if i <= length(CHANNELS(ch).LEFTMIN_VALUES) && ~isnan(CHANNELS(ch).LEFTMIN_VALUES(i))
            % leftMIN点 - 下三角标记
            scatter(CHANNELS(ch).LEFT_MIN_TARGET, CHANNELS(ch).LEFTMIN_VALUES(i), ...
                60, colors_sub(idx, :), 'filled', 'v', ...
                'MarkerEdgeColor', 'k', 'LineWidth', 1);
        end

        if i <= length(CHANNELS(ch).RIGHTMIN_VALUES) && ~isnan(CHANNELS(ch).RIGHTMIN_VALUES(i))
            % rightMIN点 - 下三角标记
            scatter(CHANNELS(ch).RIGHT_MIN_TARGET, CHANNELS(ch).RIGHTMIN_VALUES(i), ...
                60, colors_sub(idx, :), 'filled', 'v', ...
                'MarkerEdgeColor', 'k', 'LineWidth', 1);
        end
    end

    % 绘制特征点参考线
    y_limits = get(gca, 'YLim');
    plot([CHANNELS(ch).MAX_TARGET, CHANNELS(ch).MAX_TARGET], y_limits, ...
        'k--', 'LineWidth', 1, 'Color', [0.5 0.5 0.5]);
    plot([CHANNELS(ch).LEFT_MIN_TARGET, CHANNELS(ch).LEFT_MIN_TARGET], y_limits, ...
        'k--', 'LineWidth', 1, 'Color', [0.5 0.5 0.5]);
    plot([CHANNELS(ch).RIGHT_MIN_TARGET, CHANNELS(ch).RIGHT_MIN_TARGET], y_limits, ...
        'k--', 'LineWidth', 1, 'Color', [0.5 0.5 0.5]);

    hold off;
    title(sprintf('%s (%.0fkHz): 2F信号特征点提取', ...
        CHANNELS(ch).NAME, CHANNELS(ch).FREQ/1000), ...
        'FontSize', 12, 'FontWeight', 'bold');
    xlabel('时间 (s)', 'FontSize', 10);
    ylabel('I分量幅值', 'FontSize', 10);
    grid on;
    box on;

end

% 添加总标题
sgtitle(sprintf('三信道2F信号特征点提取 (显示 %d/%d 个信号段)', ...
    length(plot_indices), num_segments), 'FontSize', 14, 'FontWeight', 'bold');

fprintf('  已绘制 %d/%d 个信号段的特征点\n', length(plot_indices), num_segments);


%% Part 6.2: 三信道2F幅值时序对比（三个子图）
fprintf('\n=== 生成三信道2F幅值时序对比图 ===\n');

figure('Name', '三信道2F幅值时序对比');

for ch = 1:NUM_CHANNELS
    subplot(NUM_CHANNELS, 1, ch);
    hold on;

    % 绘制2F幅值曲线
    h_line = plot(1:num_segments, CHANNELS(ch).SECOND_HARMONIC, 'o-', ...
        'Color', CHANNELS(ch).COLOR, 'LineWidth', 1.5, ...
        'MarkerSize', 6, 'MarkerFaceColor', CHANNELS(ch).COLOR, ...
        'DisplayName', sprintf('%s 2F', CHANNELS(ch).NAME));

    % 添加均值线
    sh_mean = mean(CHANNELS(ch).SECOND_HARMONIC, 'omitnan');
    sh_std = std(CHANNELS(ch).SECOND_HARMONIC, 'omitnan');
    yline(sh_mean, '--', 'Color', CHANNELS(ch).COLOR, 'LineWidth', 2, ...
        'DisplayName', sprintf('均值: %.4f', sh_mean));

    % 添加±1σ置信区间
    y_fill = [sh_mean - sh_std, sh_mean + sh_std];
    fill([1, num_segments, num_segments, 1], ...
        [y_fill(1), y_fill(1), y_fill(2), y_fill(2)], ...
        CHANNELS(ch).COLOR, 'FaceAlpha', 0.2, 'EdgeColor', 'none', ...
        'DisplayName', '±1σ');

    hold off;
    title(sprintf('%s (%.0fkHz): 2F幅值', ...
        CHANNELS(ch).NAME, CHANNELS(ch).FREQ/1000), ...
        'FontSize', 12, 'FontWeight', 'bold');
    xlabel('信号段索引', 'FontSize', 10);
    ylabel('2F幅值', 'FontSize', 10);
    legend('Location', 'best', 'FontSize', 8);
    grid on;
    box on;


end

% 添加总标题
sgtitle('三信道2F幅值时序对比', 'FontSize', 14, 'FontWeight', 'bold');

fprintf('  2F幅值统计:\n');
for ch = 1:NUM_CHANNELS
    fprintf('    %s: 均值=%.6f, 标准差=%.6f, CV=%.2f%%\n', ...
        CHANNELS(ch).NAME, ...
        mean(CHANNELS(ch).SECOND_HARMONIC, 'omitnan'), ...
        std(CHANNELS(ch).SECOND_HARMONIC, 'omitnan'), ...
        std(CHANNELS(ch).SECOND_HARMONIC, 'omitnan') / ...
        mean(CHANNELS(ch).SECOND_HARMONIC, 'omitnan') * 100);
end


%% Part 6.3: 三信道AMP值时序对比（三个子图）
fprintf('\n=== 生成三信道AMP值时序对比图 ===\n');

figure('Name', '三信道AMP值时序对比');

for ch = 1:NUM_CHANNELS
    subplot(NUM_CHANNELS, 1, ch);
    hold on;

    % 绘制AMP值曲线
    h_line = plot(1:num_segments, CHANNELS(ch).AMP_VALUES, 'o-', ...
        'Color', CHANNELS(ch).COLOR, 'LineWidth', 1.5, ...
        'MarkerSize', 6, 'MarkerFaceColor', CHANNELS(ch).COLOR, ...
        'DisplayName', sprintf('%s AMP', CHANNELS(ch).NAME));

    % 添加均值线
    amp_mean = mean(CHANNELS(ch).AMP_VALUES, 'omitnan');
    amp_std = std(CHANNELS(ch).AMP_VALUES, 'omitnan');
    yline(amp_mean, '--', 'Color', CHANNELS(ch).COLOR, 'LineWidth', 2, ...
        'DisplayName', sprintf('均值: %.4f', amp_mean));

    % 添加±1σ置信区间
    y_fill = [amp_mean - amp_std, amp_mean + amp_std];
    fill([1, num_segments, num_segments, 1], ...
        [y_fill(1), y_fill(1), y_fill(2), y_fill(2)], ...
        CHANNELS(ch).COLOR, 'FaceAlpha', 0.2, 'EdgeColor', 'none', ...
        'DisplayName', '±1σ');

    hold off;
    title(sprintf('%s (%.0fkHz): AMP值', ...
        CHANNELS(ch).NAME, CHANNELS(ch).FREQ/1000), ...
        'FontSize', 12, 'FontWeight', 'bold');
    xlabel('信号段索引', 'FontSize', 10);
    ylabel('AMP值 (归一化)', 'FontSize', 10);
    legend('Location', 'best', 'FontSize', 8);
    grid on;
    box on;


end

% 添加总标题
sgtitle('三信道AMP值时序对比 (归一化)', 'FontSize', 14, 'FontWeight', 'bold');

fprintf('  AMP值统计:\n');
for ch = 1:NUM_CHANNELS
    fprintf('    %s: 均值=%.6f, 标准差=%.6f, CV=%.2f%%\n', ...
        CHANNELS(ch).NAME, ...
        mean(CHANNELS(ch).AMP_VALUES, 'omitnan'), ...
        std(CHANNELS(ch).AMP_VALUES, 'omitnan'), ...
        std(CHANNELS(ch).AMP_VALUES, 'omitnan') / ...
        mean(CHANNELS(ch).AMP_VALUES, 'omitnan') * 100);
end

fprintf('\n三信道特征值可视化完成\n');

%% Part 7: 保存三信道AMP值结果
fprintf('\n=== 保存三信道AMP值结果 ===\n');

% 询问用户是否保存结果
save_amp = input('是否保存AMP分析结果? (Y/N) [默认: Y]: ', 's');
if isempty(save_amp), save_amp = 'Y'; end

if strcmpi(save_amp, 'Y')
    % 根据测试类型生成文件名
    if is_static_test
        % 静态测试模式：文件名包含各气体浓度
        file_name_amp = sprintf('AMP结果_%s_%.1fppm_%.1fppm_%.1fppm_%s.txt', ...
            timestamp_str, ...
            CHANNELS(1).CONCENTRATION, ...
            CHANNELS(2).CONCENTRATION, ...
            CHANNELS(3).CONCENTRATION, ...
            timestamp_str);
    else
        % 动态测试模式
        file_name_amp = sprintf('Dynamic_AMP结果_%s.txt', timestamp_str);
    end

    % 创建表格数据：索引 + 三信道AMP值
    indices = (1:num_segments)';
    T_amp = table(indices, ...
        CHANNELS(1).AMP_VALUES, ...
        CHANNELS(2).AMP_VALUES, ...
        CHANNELS(3).AMP_VALUES, ...
        'VariableNames', {'Index', 'CO2_AMP', 'N2O_AMP', 'CO_AMP'});

    % 写入文件，使用制表符分隔
    writetable(T_amp, file_name_amp, 'Delimiter', '\t');

    % 在文件末尾追加各信道的统计信息
    fid = fopen(file_name_amp, 'a');

    % 写入分隔线
    fprintf(fid, '\n========================================\n');
    fprintf(fid, 'Statistical Summary\n');
    fprintf(fid, '========================================\n');

    % 写入各信道统计信息
    for ch = 1:NUM_CHANNELS
        amp_mean = mean(CHANNELS(ch).AMP_VALUES, 'omitnan');
        amp_std = std(CHANNELS(ch).AMP_VALUES, 'omitnan');
        amp_cv = (amp_std / amp_mean) * 100;

        fprintf(fid, '%s\tMean\t%.6f\tStd\t%.6f\tCV_percent\t%.2f\n', ...
            CHANNELS(ch).NAME, amp_mean, amp_std, amp_cv);
    end

    % 写入总体信息
    fprintf(fid, '----------------------------------------\n');
    fprintf(fid, 'Signal Segments\t%d\n', num_segments);
    if is_static_test
        fprintf(fid, 'Test Type\tStatic\n');
    else
        fprintf(fid, 'Test Type\tDynamic\n');
    end

    if is_static_test
        fprintf(fid, 'CO2 Concentration\t%.1f ppm\n', CHANNELS(1).CONCENTRATION);
        fprintf(fid, 'N2O Concentration\t%.1f ppm\n', CHANNELS(2).CONCENTRATION);
        fprintf(fid, 'CO Concentration\t%.1f ppm\n', CHANNELS(3).CONCENTRATION);
    end

    fclose(fid);

    % 在命令行显示保存的内容预览
    fprintf('\n保存的文件内容预览:\n');
    fprintf('----------------------------------------\n');
    fprintf('Index\t\tCO2_AMP\t\tN2O_AMP\t\tCO_AMP\n');
    fprintf('----------------------------------------\n');

    for i = 1:min(5, num_segments)
        fprintf('%d\t\t%.6f\t%.6f\t%.6f\n', ...
            i, ...
            CHANNELS(1).AMP_VALUES(i), ...
            CHANNELS(2).AMP_VALUES(i), ...
            CHANNELS(3).AMP_VALUES(i));
    end
    if num_segments > 5
        fprintf('...\t(共 %d 个信号段)\n', num_segments);
    end
    fprintf('----------------------------------------\n');
    fprintf('AMP分析结果已保存至: %s\n', file_name_amp);
else
    fprintf('已跳过保存AMP结果。\n');
end
