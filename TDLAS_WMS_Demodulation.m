% =========================================================================
% TDLAS_WMS_Demodulation.m
% 波长调制光谱(WMS)信号解调程序
% 
% 作者    : https://github.com/RomaneeeCon
% 版本    : V1.0
% 日期    : 2024-12-29
% 
% 功能描述:
%   本程序用于处理TDLAS-WMS(波长调制光谱)实验数据，实现从原始调制
%   信号到2F谐波信号的锁相解调，并提取AMP(幅值)特征用于浓度反演。
% 
% 核心特点:
%   - 支持TXT和CSV双格式数据导入
%   - 自动相位校正确保信号一致性
%   - 自动特征提取(MAX, leftMIN, rightMIN)
%   - 支持静态测试(带浓度标注)和动态测试
% 
% 处理流程:
%   1. 数据导入      - 读取原始WMS信号
%   2. 信号预处理    - 分段、对齐、清洗
%   3. 锁相解调      - 提取2F谐波信号(I/Q分量)
%   4. 相位校正      - 自动相位对齐
%   5. 降采样        - 统一数据长度
%   6. 特征提取      - 提取MAX, MIN特征点
%   7. AMP计算       - 计算幅值特征
%   8. 结果可视化    - 显示处理结果
% 
% 输入:
%   - 交互式选择TXT/CSV格式数据文件
%   - 用户输入测试类型和气体浓度(静态测试)
% 
% 输出:
%   - 2F谐波波形数据
%   - AMP特征值及统计信息
%   - 处理过程可视化图形
% 
% 依赖:
%   - MATLAB R2020b或更高版本
%   - Signal Processing Toolbox
% 
% 使用示例:
%   >> TDLAS_WMS_Demodulation
% 
% 版本历史:
%   V1.0 (2024-12-29) - 初始版本，基于1229_V1重构
% =========================================================================

%% 程序初始化
clc;                    % 清除命令窗口
close all;              % 关闭所有图形窗口

%% 配置参数定义
% WMS解调配置参数
CONFIG.THRESHOLD_HIGH = 0.05;           % 高阈值，用于触发信号检测 [V]
CONFIG.THRESHOLD_LOW = 0.02;            % 低阈值，用于重置检测状态 [V]
CONFIG.TARGET_DURATION = 0.16;          % 目标信号持续时间 [s]
CONFIG.TOLERANCE = 0.01 * CONFIG.TARGET_DURATION;  % 持续时间容差 [s]
CONFIG.TRIM_START = 0.02;               % 起始段去除比例 [0-1]
CONFIG.TRIM_END = 0.02;                 % 结束段去除比例 [0-1]

% 锁相放大器配置
LOCKIN.HARMONIC = 2;                    % 谐波次数 (2F)
LOCKIN.FREQUENCY = 5017.5;              % 调制频率 [Hz]
LOCKIN.PHASE_COMPENSATION = 0;          % 初始相位补偿 [度]
LOCKIN.FILTER_FP = 50;                  % 低通滤波器通带 [Hz]
LOCKIN.FILTER_FSB = 240;                % 低通滤波器阻带 [Hz]
LOCKIN.TARGET_TIME = 0.0902;            % 目标时间点(用于相位校正) [s]

% 特征提取配置
FEATURE.MAX_TARGET = 0.0902;            % MAX特征目标时间 [s]
FEATURE.LEFT_MIN_TARGET = 0.0607;       % 左侧MIN目标时间 [s]
FEATURE.RIGHT_MIN_TARGET = 0.1218;      % 右侧MIN目标时间 [s]
FEATURE.SEARCH_WINDOW = 0.002;          % 极值搜索窗口半径 [s]

% 相位校正时间窗口
CORR_WINDOW_START = LOCKIN.TARGET_TIME * 0.8;
CORR_WINDOW_END = LOCKIN.TARGET_TIME * 1.2;

%% 测试类型选择
fprintf('========================================\n');
fprintf('    TDLAS WMS信号解调程序\n');
fprintf('    作者: https://github.com/RomaneeeCon\n');
fprintf('========================================\n\n');

fprintf('=== 测试类型选择 ===\n');
fprintf('  1 - 静态测试 (需要输入气体浓度)\n');
fprintf('  2 - 动态测试 (无需输入气体浓度)\n');

% 获取用户输入
test_type = input('请选择测试类型 (1 或 2): ');

% 根据测试类型设置参数
if test_type == 1
    % 静态测试模式
    is_static_test = true;
    
    % 获取气体浓度输入
    gas_concentration = input('请输入气体浓度 [ppm]: ');
    
    % 验证输入有效性
    if isnan(gas_concentration) || gas_concentration < 0
        error('输入的浓度值无效！浓度必须为非负数。');
    end
    
    fprintf('气体浓度设置为: %.2f ppm\n', gas_concentration);
    
elseif test_type == 2
    % 动态测试模式
    is_static_test = false;
    gas_concentration = NaN;  % 动态测试不使用浓度值
    fprintf('动态测试模式，无需输入气体浓度\n');
    
else
    % 无效输入
    error('无效的测试类型选择，请输入 1 或 2。');
end

% 生成统一时间戳
global_timestamp = datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss');
timestamp_str = string(global_timestamp);

%% 数据导入
fprintf('\n=== 数据导入 ===\n');

% 使用文件对话框选择数据文件
[file_name, folder_path] = uigetfile(...
    {'*.TXT;*.txt', 'Text Files (*.TXT, *.txt)'; ...
     '*.CSV;*.csv', 'CSV Files (*.CSV, *.csv)'; ...
     '*.*', 'All Files (*.*)'}, ...
    '选择WMS数据文件', ...
    pwd);

% 检查用户是否取消了选择
if file_name == 0
    error('未选择文件，程序终止。');
end

% 构建完整文件路径
file_path = fullfile(folder_path, file_name);

% 验证文件是否存在
if ~isfile(file_path)
    error('文件不存在，请检查路径是否正确: %s', file_path);
end

% 获取文件扩展名
[~, ~, file_ext] = fileparts(file_name);
file_ext = lower(file_ext);

% 根据文件类型选择读取方式
switch file_ext
    case '.csv'
        % CSV文件：跳过前3行头部信息
        raw_data = readmatrix(file_path, 'HeaderLines', 3);
        fprintf('CSV文件导入中，已跳过前3行头部信息...\n');
        
    case {'.txt', '.TXT'}
        % TXT文件：直接读取
        raw_data = readmatrix(file_path);
        fprintf('TXT文件导入中...\n');
        
    otherwise
        error('不支持的文件格式: %s，请选择TXT或CSV文件。', file_ext);
end

% 验证数据有效性
if isempty(raw_data) || size(raw_data, 1) < 2
    error('数据文件为空或数据行数不足，请检查文件内容。');
end

if size(raw_data, 2) < 2
    error('数据文件至少需要2列（时间和幅值），当前只有%d列。', size(raw_data, 2));
end

% 提取时间和幅值数据
time_vector = raw_data(:, 1);           % 时间向量 [s]
raw_amplitude = raw_data(:, 2);         % 原始信号幅值 [V]

fprintf('成功导入数据文件: %s\n', file_name);
fprintf('数据点数: %d\n', length(time_vector));

%% 采样频率计算
fprintf('\n=== 采样频率计算 ===\n');

% 检查时间向量长度
if length(time_vector) < 2
    error('时间序列长度不足，无法计算采样频率！');
end

% 计算采样频率
sampling_freq = 1 / (time_vector(2) - time_vector(1));
fprintf('采样频率: %.2f Hz\n', sampling_freq);

%% 信号分段检测
fprintf('\n=== 信号分段检测 ===\n');

% 预分配数组存储检测结果
max_segments = ceil(length(raw_amplitude) / (CONFIG.TARGET_DURATION * sampling_freq));
start_index = nan(max_segments, 1);
end_index = nan(max_segments, 1);
signal_segments = cell(max_segments, 1);

% 初始化检测状态
triggered = false;      % 触发状态标志
segment_count = 0;      % 检测到的片段计数

% 遍历信号进行阈值检测
for i = 1:length(raw_amplitude)
    if raw_amplitude(i) > CONFIG.THRESHOLD_HIGH && ~triggered
        % 检测到上升沿触发
        triggered = true;
        segment_count = segment_count + 1;
        start_index(segment_count) = i;
        
    elseif raw_amplitude(i) < CONFIG.THRESHOLD_LOW && triggered
        % 检测到下降沿重置
        triggered = false;
        end_index(segment_count) = i;
        signal_segments{segment_count} = raw_amplitude(start_index(segment_count):end_index(segment_count));
    end
end

% 处理未正常结束的片段
valid_segments = isfinite(start_index(1:segment_count)) & isfinite(end_index(1:segment_count));
start_index = start_index(valid_segments);
end_index = end_index(valid_segments);
signal_segments = signal_segments(valid_segments);
segment_count = sum(valid_segments);

fprintf('初步检测到 %d 个信号片段\n', segment_count);

%% 片段筛选
fprintf('\n=== 片段筛选 ===\n');

filtered_segments = {};         % 筛选后的信号片段
filtered_start_idx = [];        % 筛选后的起始索引
filtered_end_idx = [];          % 筛选后的结束索引

for i = 1:segment_count
    % 计算当前片段的持续时间
    segment_time = time_vector(start_index(i):end_index(i));
    segment_duration = segment_time(end) - segment_time(1);
    
    % 应用筛选条件
    if abs(segment_duration - CONFIG.TARGET_DURATION) <= CONFIG.TOLERANCE
        filtered_segments{end+1} = signal_segments{i};
        filtered_start_idx = [filtered_start_idx, start_index(i)];
        filtered_end_idx = [filtered_end_idx, end_index(i)];
    end
end

num_valid_segments = length(filtered_segments);
fprintf('通过筛选的片段数: %d\n', num_valid_segments);

% 检查是否有有效片段
if num_valid_segments == 0
    error('未找到符合条件的信号片段，请调整阈值参数。');
end

%% 信号可视化(原始信号和检测点)
figure('Name', 'WMS信号处理过程', 'Position', [100, 100, 1000, 600]);

% 子图1: 原始信号和检测点
subplot(2, 1, 1);
plot(time_vector, raw_amplitude, 'b-', 'LineWidth', 0.8, 'DisplayName', '原始信号');
hold on;
plot(time_vector(filtered_start_idx), raw_amplitude(filtered_start_idx), ...
    'go', 'MarkerSize', 8, 'LineWidth', 2, 'DisplayName', '起始点');
plot(time_vector(filtered_end_idx), raw_amplitude(filtered_end_idx), ...
    'ro', 'MarkerSize', 8, 'LineWidth', 2, 'DisplayName', '结束点');
title('原始WMS信号及检测点', 'FontSize', 14, 'FontWeight', 'bold');
xlabel('时间 [s]', 'FontSize', 12);
ylabel('幅值 [V]', 'FontSize', 12);
legend('Location', 'best');
grid on;
hold off;

% 子图2: 提取的信号片段
subplot(2, 1, 2);
hold on;
colors = lines(num_valid_segments);
for i = 1:num_valid_segments
    segment_time = time_vector(filtered_start_idx(i):filtered_end_idx(i));
    plot(segment_time, filtered_segments{i}, ...
        'Color', colors(i, :), 'LineWidth', 1.5, 'DisplayName', sprintf('片段%d', i));
end
title('提取的信号片段', 'FontSize', 14, 'FontWeight', 'bold');
xlabel('时间 [s]', 'FontSize', 12);
ylabel('幅值 [V]', 'FontSize', 12);
grid on;
hold off;

%% 信号对齐与清洗
fprintf('\n=== 信号对齐与清洗 ===\n');

% 计算平均周期
segment_durations = zeros(num_valid_segments, 1);
for i = 1:num_valid_segments
    segment_durations(i) = time_vector(filtered_end_idx(i)) - time_vector(filtered_start_idx(i));
end
mean_period = mean(segment_durations);

% 信号裁剪
trimmed_segments = {};
trimmed_time = {};

for i = 1:num_valid_segments
    segment_raw = filtered_segments{i};
    seg_len = length(segment_raw);
    
    % 计算裁剪点数
    start_cut = floor(seg_len * CONFIG.TRIM_START);
    end_cut = floor(seg_len * CONFIG.TRIM_END);
    
    % 执行裁剪
    trimmed_segments{i} = segment_raw(start_cut+1 : end-start_cut);
    trimmed_time{i} = (0:length(trimmed_segments{i})-1) / sampling_freq;
end

% 找到最小长度并创建统一时间轴
min_length = min(cellfun(@length, trimmed_segments));
cleaned_duration = mean_period * (1 - CONFIG.TRIM_START - CONFIG.TRIM_END);
uniform_time = linspace(0, cleaned_duration, min_length);

% 构建数据矩阵
cleaned_matrix = NaN(num_valid_segments, min_length);
for i = 1:num_valid_segments
    cleaned_matrix(i, :) = trimmed_segments{i}(1:min_length);
end

fprintf('清洗后数据矩阵大小: %d x %d\n', size(cleaned_matrix, 1), size(cleaned_matrix, 2));

%% 锁相解调(2F提取)
fprintf('\n=== 锁相解调(2F提取) ===\n');

% 设计FIR低通滤波器
[filter_order, ~, beta, ~] = kaiserord([LOCKIN.FILTER_FP, LOCKIN.FILTER_FSB], ...
    [1, 0], [0.0001, 0.01], sampling_freq);
filter_order = filter_order + mod(filter_order, 2);
fir_coeff = single(fir1(filter_order, LOCKIN.FILTER_FP/(sampling_freq/2), kaiser(filter_order+1, beta), 'low'));

fprintf('FIR滤波器阶数: %d\n', filter_order);

% 初始化解调结果数组
I_component = zeros(num_valid_segments, min_length);
Q_component = zeros(num_valid_segments, min_length);
amplitude = zeros(num_valid_segments, min_length);
phase = zeros(num_valid_segments, min_length);

% 第一次解调(初始相位)
phase_rad_init = deg2rad(LOCKIN.PHASE_COMPENSATION);
ref_arg = 2 * pi * LOCKIN.HARMONIC * LOCKIN.FREQUENCY * uniform_time + phase_rad_init;
ref_cos = cos(ref_arg);
ref_sin = sin(ref_arg);

for i = 1:num_valid_segments
    signal = cleaned_matrix(i, :);
    I_component(i, :) = filter(fir_coeff, 1, signal .* ref_cos);
    Q_component(i, :) = filter(fir_coeff, 1, signal .* ref_sin);
    amplitude(i, :) = 2 * sqrt(I_component(i, :).^2 + Q_component(i, :).^2);
    phase(i, :) = rad2deg(atan2(Q_component(i, :), I_component(i, :)));
end

%% 相位校正
fprintf('\n=== 相位校正 ===\n');

% 初始化校正后的结果
I_corrected = zeros(num_valid_segments, min_length);
Q_corrected = zeros(num_valid_segments, min_length);
amplitude_corrected = zeros(num_valid_segments, min_length);
phase_corrected = zeros(num_valid_segments, min_length);

% 定义校正窗口
window_mask = (uniform_time >= CORR_WINDOW_START) & (uniform_time <= CORR_WINDOW_END);
window_idx = find(window_mask);

% 对每个片段进行相位校正
for i = 1:num_valid_segments
    % 在窗口内找到最大值位置
    [~, rel_idx] = max(amplitude(i, window_idx));
    max_idx = window_idx(rel_idx);
    
    % 计算校正角度
    correction_angle = deg2rad(phase(i, max_idx));
    
    % 生成校正后的参考信号
    ref_arg_corr = 2 * pi * LOCKIN.HARMONIC * LOCKIN.FREQUENCY * uniform_time - correction_angle;
    
    % 重新解调
    I_corrected(i, :) = filter(fir_coeff, 1, cleaned_matrix(i, :) .* cos(ref_arg_corr));
    Q_corrected(i, :) = filter(fir_coeff, 1, cleaned_matrix(i, :) .* sin(ref_arg_corr));
    
    % 计算校正后的幅值和相位
    amplitude_corrected(i, :) = 2 * sqrt(I_corrected(i, :).^2 + Q_corrected(i, :).^2);
    phase_rad = atan2(Q_corrected(i, :), I_corrected(i, :));
    
    % 检查相位翻转
    [~, rel_idx_corr] = max(amplitude_corrected(i, window_idx));
    max_idx_corr = window_idx(rel_idx_corr);
    if abs(rad2deg(phase_rad(max_idx_corr))) > 150
        phase_rad = phase_rad + pi;
    end
    phase_corrected(i, :) = rad2deg(phase_rad);
end

fprintf('相位校正完成\n');

%% 降采样
fprintf('\n=== 降采样处理 ===\n');

target_points = 500;
time_sampled = linspace(0, cleaned_duration, target_points);
I_sampled = zeros(num_valid_segments, target_points, 'single');

for i = 1:num_valid_segments
    I_sampled(i, :) = single(interp1(uniform_time, I_corrected(i, :), time_sampled, 'linear'));
end

fprintf('降采样后点数: %d\n', target_points);

%% 特征提取与AMP计算
fprintf('\n=== 特征提取与AMP计算 ===\n');

% 准备分析数据(转置为列向量)
analysis_matrix = I_sampled';
time_analysis = time_sampled';

% 初始化特征数组
MAX_values = nan(num_valid_segments, 1);
leftMIN_values = nan(num_valid_segments, 1);
rightMIN_values = nan(num_valid_segments, 1);
MAX_times = nan(num_valid_segments, 1);
leftMIN_times = nan(num_valid_segments, 1);
rightMIN_times = nan(num_valid_segments, 1);

% 极值搜索
for i = 1:num_valid_segments
    current_signal = analysis_matrix(:, i);
    
    % 1. 查找 MAX
    t_start = FEATURE.MAX_TARGET - FEATURE.SEARCH_WINDOW;
    t_end = FEATURE.MAX_TARGET + FEATURE.SEARCH_WINDOW;
    mask = (time_analysis >= t_start) & (time_analysis <= t_end);
    if any(mask)
        [val, idx_in_mask] = max(current_signal(mask));
        idx_global = find(mask);
        MAX_values(i) = val;
        MAX_times(i) = time_analysis(idx_global(idx_in_mask));
    end
    
    % 2. 查找 leftMIN
    t_start = FEATURE.LEFT_MIN_TARGET - FEATURE.SEARCH_WINDOW;
    t_end = FEATURE.LEFT_MIN_TARGET + FEATURE.SEARCH_WINDOW;
    mask = (time_analysis >= t_start) & (time_analysis <= t_end);
    if any(mask)
        [val, idx_in_mask] = min(current_signal(mask));
        idx_global = find(mask);
        leftMIN_values(i) = val;
        leftMIN_times(i) = time_analysis(idx_global(idx_in_mask));
    end
    
    % 3. 查找 rightMIN
    t_start = FEATURE.RIGHT_MIN_TARGET - FEATURE.SEARCH_WINDOW;
    t_end = FEATURE.RIGHT_MIN_TARGET + FEATURE.SEARCH_WINDOW;
    mask = (time_analysis >= t_start) & (time_analysis <= t_end);
    if any(mask)
        [val, idx_in_mask] = min(current_signal(mask));
        idx_global = find(mask);
        rightMIN_values(i) = val;
        rightMIN_times(i) = time_analysis(idx_global(idx_in_mask));
    end
end

% 计算AMP值
AMP_values = MAX_values - (leftMIN_values + rightMIN_values) / 2;
valid_mask = ~isnan(AMP_values);
AMP_clean = AMP_values(valid_mask);
valid_count = sum(valid_mask);

% 统计指标
AMP_mean = mean(AMP_clean);
AMP_std = std(AMP_clean);
AMP_CV = (AMP_std / AMP_mean) * 100;

%% 结果显示
fprintf('\n========================================\n');
fprintf('    AMP分析结果\n');
fprintf('========================================\n');
if is_static_test
    fprintf('气体浓度: %.2f ppm\n', gas_concentration);
end
fprintf('有效信号数: %d / %d\n', valid_count, num_valid_segments);
fprintf('AMP平均值: %.6f\n', AMP_mean);
fprintf('AMP标准差: %.6f\n', AMP_std);
fprintf('AMP变异系数(CV): %.2f%%\n', AMP_CV);
fprintf('========================================\n');

%% 结果可视化

% 图1: 锁相解调结果
figure('Name', '锁相解调结果', 'Position', [150, 150, 900, 700]);

subplot(4, 1, 1);
plot(time_sampled, I_corrected', 'LineWidth', 1);
title('校正后 I分量', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('时间 [s]');
ylabel('幅值');
grid on;

subplot(4, 1, 2);
plot(time_sampled, Q_corrected', 'LineWidth', 1);
title('校正后 Q分量', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('时间 [s]');
ylabel('幅值');
grid on;

subplot(4, 1, 3);
plot(time_sampled, amplitude_corrected', 'LineWidth', 1);
title('校正后 幅值', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('时间 [s]');
ylabel('幅值');
grid on;

subplot(4, 1, 4);
plot(time_sampled, phase_corrected', 'LineWidth', 1);
title('校正后 相位', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('时间 [s]');
ylabel('相位 [度]');
grid on;

% 图2: 特征点标记
figure('Name', '2F信号特征点', 'Position', [200, 200, 900, 500]);
hold on;
for i = 1:num_valid_segments
    plot(time_analysis, analysis_matrix(:, i), 'Color', colors(i, :), 'LineWidth', 1);
    if valid_mask(i)
        scatter(MAX_times(i), MAX_values(i), 50, colors(i, :), 'filled', '^', 'MarkerEdgeColor', 'k');
        scatter(leftMIN_times(i), leftMIN_values(i), 50, colors(i, :), 'filled', 'v', 'MarkerEdgeColor', 'k');
        scatter(rightMIN_times(i), rightMIN_values(i), 50, colors(i, :), 'filled', 'v', 'MarkerEdgeColor', 'k');
    end
end
title('2F信号及其特征点', 'FontSize', 14, 'FontWeight', 'bold');
xlabel('时间 [s]', 'FontSize', 12);
ylabel('幅值', 'FontSize', 12);
grid on;
hold off;

% 图3: AMP分布
figure('Name', 'AMP分布统计', 'Position', [250, 250, 800, 400]);
hold on;
plot(1:num_valid_segments, AMP_values, 'bo-', 'LineWidth', 1.5, 'MarkerFaceColor', 'b');
yline(AMP_mean, 'r--', 'LineWidth', 2, 'DisplayName', sprintf('Mean: %.4f', AMP_mean));
fill([1:num_valid_segments, num_valid_segments:-1:1], ...
    [repmat(AMP_mean+AMP_std, 1, num_valid_segments), repmat(AMP_mean-AMP_std, 1, num_valid_segments)], ...
    [1, 0.8, 0.8], 'FaceAlpha', 0.3, 'EdgeColor', 'none');
title(sprintf('AMP值分布 (CV=%.2f%%)', AMP_CV), 'FontSize', 14, 'FontWeight', 'bold');
xlabel('信号索引', 'FontSize', 12);
ylabel('AMP', 'FontSize', 12);
legend('各组AMP', '平均值', '±1σ', 'Location', 'best');
grid on;
hold off;

%% 程序结束
fprintf('\n程序执行完毕。\n');
