% =========================================================================
% TDLAS_DAS_Demodulation.m
% 直接吸收光谱(DAS)信号解调程序
% 
% 作者    : https://github.com/RomaneeeCon
% 版本    : V1.0
% 日期    : 2024-12-04
% 
% 功能描述:
%   本程序用于处理DAS(直接吸收光谱)实验数据，从原始信号中提取有效
%   信号片段并进行预处理，为后续的浓度反演分析做准备。
% 
% 核心特点:
%   - 全程保留信号的绝对幅值，不进行标准化操作
%   - 基于双阈值检测自动提取有效信号片段
%   - 支持信号对齐、清洗和降采样处理
%   - 支持静态测试(带浓度标注)和动态测试两种模式
% 
% 处理流程:
%   1. 数据导入      - 从TXT文件读取DAS信号时间序列
%   2. 信号去噪      - 移动平均滤波
%   3. 信号分段      - 双阈值检测提取有效片段
%   4. 片段筛选      - 根据长度和持续时间筛选
%   5. 信号对齐      - 将各片段对齐到时间零点
%   6. 信号清洗      - 去除首尾干扰段
%   7. 降采样        - 降采样到目标点数
%   8. 数据保存      - 保存为CSV格式文件
% 
% 输入:
%   - 交互式选择TXT格式DAS数据文件
%   - 用户输入测试类型和气体浓度(静态测试)
% 
% 输出:
%   - CSV格式处理结果文件
%   - 信号可视化图形
% 
% 依赖:
%   - MATLAB R2020b或更高版本
%   - Signal Processing Toolbox (推荐)
% 
% 使用示例:
%   >> TDLAS_DAS_Demodulation
% 
% 版本历史:
%   V1.0 (2024-12-04) - 初始版本，基于1204_V1重构
% =========================================================================

%% 程序初始化
% 清除工作区和命令窗口，关闭所有图形窗口
clc;                    % 清除命令窗口
close all;              % 关闭所有图形窗口

%% 配置参数定义
% 使用结构体组织配置参数，便于管理和传递
CONFIG.THRESHOLD_HIGH = 0.05;           % 高阈值，用于触发信号检测 [V]
CONFIG.THRESHOLD_LOW = 0.04;            % 低阈值，用于重置检测状态 [V]
CONFIG.TARGET_DURATION = 0.16;          % 目标信号持续时间 [s]
CONFIG.TOLERANCE = 0.01 * CONFIG.TARGET_DURATION;  % 持续时间容差 [s]
CONFIG.TRIM_START = 0.03;               % 起始段去除比例 [0-1]
CONFIG.TRIM_END = 0.03;                 % 结束段去除比例 [0-1]
CONFIG.MIN_SIGNAL_LENGTH = 100;         % 最小信号长度 [点数]
CONFIG.DOWNSAMPLE_TARGET_POINTS = 500;  % 降采样目标点数
CONFIG.DOWNSAMPLE_METHOD = 'linear';    % 降采样方法: 'linear', 'pchip', 'spline'

%% 测试类型选择
% 根据实验类型选择不同的处理模式
fprintf('========================================\n');
fprintf('    TDLAS DAS信号解调程序\n');
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

%% 数据导入
% 使用文件对话框选择数据文件
fprintf('\n=== 数据导入 ===\n');

[fileName, folderPath] = uigetfile(...
    {'*.TXT;*.txt', 'Text Files (*.TXT, *.txt)'; '*.*', 'All Files (*.*)'}, ...
    '选择DAS数据文件', ...
    pwd);

% 检查用户是否取消了选择
if fileName == 0
    error('未选择文件，程序终止。');
end

% 构建完整文件路径
filePath = fullfile(folderPath, fileName);

% 验证文件是否存在
if ~isfile(filePath)
    error('文件不存在，请检查路径是否正确: %s', filePath);
end

% 读取数据文件
% 假设文件格式: 第一列为时间，第二列为信号幅值
DAS_data = readmatrix(filePath);

% 提取时间和幅值数据
time_vector = DAS_data(:, 1);           % 时间向量 [s]
raw_amplitude = DAS_data(:, 2);         % 原始信号幅值 [V]

fprintf('成功导入数据文件: %s\n', fileName);
fprintf('数据点数: %d\n', length(time_vector));

%% 采样频率计算
% 计算采样频率用于后续处理

% 检查时间向量长度
if length(time_vector) < 2
    error('时间序列长度不足，无法计算采样频率！');
end

% 计算采样间隔和采样频率
delta_t = time_vector(2) - time_vector(1);  % 采样间隔 [s]
sampling_freq = 1 / delta_t;                % 采样频率 [Hz]

fprintf('采样间隔: %.6f s\n', delta_t);
fprintf('采样频率: %.2f Hz\n', sampling_freq);

%% 信号去噪处理
% 使用移动平均滤波进行简单去噪
fprintf('\n=== 信号预处理 ===\n');

window_size = 5;  % 移动平均窗口大小
filtered_amplitude = movmean(raw_amplitude, window_size);  % 移动平均滤波

fprintf('完成移动平均滤波 (窗口大小: %d)\n', window_size);

%% 信号分段检测
% 基于双阈值检测提取有效信号片段
fprintf('\n=== 信号分段检测 ===\n');

% 预分配数组存储检测结果
max_segments = ceil(length(filtered_amplitude) / (CONFIG.TARGET_DURATION * sampling_freq));
start_index = nan(max_segments, 1);
end_index = nan(max_segments, 1);
signal_segments = cell(max_segments, 1);

% 初始化检测状态
triggered = false;      % 触发状态标志
segment_count = 0;      % 检测到的片段计数

% 遍历信号进行阈值检测
for i = 1:length(filtered_amplitude)
    if filtered_amplitude(i) > CONFIG.THRESHOLD_HIGH && ~triggered
        % 检测到上升沿触发
        triggered = true;
        segment_count = segment_count + 1;
        start_index(segment_count) = i;
        
    elseif filtered_amplitude(i) < CONFIG.THRESHOLD_LOW && triggered
        % 检测到下降沿重置
        triggered = false;
        end_index(segment_count) = i;
        
        % 存储原始信号段(非滤波后的)
        signal_segments{segment_count} = raw_amplitude(start_index(segment_count):end_index(segment_count));
    end
end

% 处理未正常结束的片段(数据末尾)
valid_segments = isfinite(start_index(1:segment_count)) & isfinite(end_index(1:segment_count));
start_index = start_index(valid_segments);
end_index = end_index(valid_segments);
signal_segments = signal_segments(valid_segments);
segment_count = sum(valid_segments);

fprintf('初步检测到 %d 个信号片段\n', segment_count);

%% 片段筛选
% 根据持续时间和长度筛选高质量片段
fprintf('\n=== 片段筛选 ===\n');

filtered_segments = {};         % 筛选后的信号片段
filtered_start_idx = [];        % 筛选后的起始索引
filtered_end_idx = [];          % 筛选后的结束索引

for i = 1:segment_count
    % 计算当前片段的持续时间
    segment_time = time_vector(start_index(i):end_index(i));
    segment_duration = segment_time(end) - segment_time(1);
    segment_length = length(signal_segments{i});
    
    % 应用筛选条件
    duration_ok = abs(segment_duration - CONFIG.TARGET_DURATION) <= CONFIG.TOLERANCE;
    length_ok = segment_length >= CONFIG.MIN_SIGNAL_LENGTH;
    
    if duration_ok && length_ok
        % 通过筛选，保留该片段
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
% 创建图形窗口显示处理过程
figure('Name', 'DAS信号处理过程', 'Position', [100, 100, 1000, 800]);

% 子图1: 原始信号和检测点
subplot(3, 1, 1);
plot(time_vector, raw_amplitude, 'b-', 'LineWidth', 0.8, 'DisplayName', '原始信号');
hold on;
plot(time_vector, filtered_amplitude, 'r-', 'LineWidth', 1.2, 'DisplayName', '滤波信号');
plot(time_vector(filtered_start_idx), raw_amplitude(filtered_start_idx), ...
    'go', 'MarkerSize', 8, 'LineWidth', 2, 'DisplayName', '起始点');
plot(time_vector(filtered_end_idx), raw_amplitude(filtered_end_idx), ...
    'ro', 'MarkerSize', 8, 'LineWidth', 2, 'DisplayName', '结束点');
title('原始DAS信号及检测点', 'FontSize', 14, 'FontWeight', 'bold');
xlabel('时间 [s]', 'FontSize', 12);
ylabel('幅值 [V]', 'FontSize', 12);
legend('Location', 'best');
grid on;
hold off;

% 子图2: 提取的信号片段
subplot(3, 1, 2);
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

%% 信号对齐
% 将各片段对齐到时间零点
fprintf('\n=== 信号对齐 ===\n');

aligned_segments = {};      % 对齐后的信号
aligned_time = {};          % 对齐后的时间

for i = 1:num_valid_segments
    % 提取当前片段的时间
    segment_time = time_vector(filtered_start_idx(i):filtered_end_idx(i));
    
    % 时间轴平移到零点
    aligned_time{i} = segment_time - segment_time(1);
    aligned_segments{i} = filtered_segments{i};
end

fprintf('完成 %d 个片段的时间对齐\n', num_valid_segments);

%% 计算信号统计信息
% 计算平均持续时间
segment_durations = zeros(num_valid_segments, 1);
for i = 1:num_valid_segments
    segment_durations(i) = aligned_time{i}(end) - aligned_time{i}(1);
end
mean_duration = mean(segment_durations);
fprintf('平均信号持续时间: %.4f s\n', mean_duration);

%% 信号清洗
% 去除首尾干扰段
fprintf('\n=== 信号清洗 ===\n');

trimmed_segments = {};      % 清洗后的信号
trimmed_time = {};          % 清洗后的时间
trim_start_positions = [];  % 起始位置记录
trim_end_positions = [];    % 结束位置记录

for i = 1:num_valid_segments
    % 获取当前片段
    current_time = aligned_time{i};
    current_signal = aligned_segments{i};
    total_points = length(current_time);
    
    % 计算需要去除的点数
    points_to_remove_start = floor(total_points * CONFIG.TRIM_START);
    points_to_remove_end = floor(total_points * CONFIG.TRIM_END);
    
    % 确保不会去除过多数据
    remaining_points = total_points - points_to_remove_start - points_to_remove_end;
    if remaining_points < CONFIG.MIN_SIGNAL_LENGTH
        points_to_remove_start = max(0, total_points - CONFIG.MIN_SIGNAL_LENGTH - points_to_remove_end);
    end
    
    % 执行裁剪
    trim_start_idx = points_to_remove_start + 1;
    trim_end_idx = total_points - points_to_remove_end;
    
    trimmed_time{i} = current_time(trim_start_idx:trim_end_idx);
    trimmed_segments{i} = current_signal(trim_start_idx:trim_end_idx);
    
    % 记录位置
    trim_start_positions = [trim_start_positions, trimmed_time{i}(1)];
    trim_end_positions = [trim_end_positions, trimmed_time{i}(end)];
end

% 找到最小片段长度
min_segment_length = min(cellfun(@length, trimmed_segments));
fprintf('清洗后最小片段长度: %d 点\n', min_segment_length);
fprintf('去除比例: 起始 %.1f%%, 结束 %.1f%%\n', CONFIG.TRIM_START*100, CONFIG.TRIM_END*100);

% 子图3: 清洗后的信号
subplot(3, 1, 3);
hold on;
for i = 1:num_valid_segments
    plot(trimmed_time{i}, trimmed_segments{i}, ...
        'Color', colors(i, :), 'LineWidth', 1.5);
end
xline(trim_start_positions(1), '--k', 'LineWidth', 1.5, 'Label', '裁剪起始');
xline(trim_end_positions(1), '--k', 'LineWidth', 1.5, 'Label', '裁剪结束');
title('清洗后的信号片段(原始幅值)', 'FontSize', 14, 'FontWeight', 'bold');
xlabel('时间 [s]', 'FontSize', 12);
ylabel('幅值 [V]', 'FontSize', 12);
grid on;
hold off;

%% 构建统一数据矩阵
fprintf('\n=== 构建数据矩阵 ===\n');

% 计算实际清洗后的持续时间
cleaned_duration = mean_duration * (1 - CONFIG.TRIM_START - CONFIG.TRIM_END);

% 创建统一时间轴
uniform_time = linspace(0, cleaned_duration, min_segment_length);

% 初始化数据矩阵
signals_matrix = nan(num_valid_segments, min_segment_length);

% 填充数据矩阵
for i = 1:num_valid_segments
    current_length = length(trimmed_segments{i});
    
    if current_length >= min_segment_length
        % 直接截取
        signals_matrix(i, :) = trimmed_segments{i}(1:min_segment_length);
    else
        % 长度不足，进行插值
        signals_matrix(i, :) = interp1(trimmed_time{i}, trimmed_segments{i}, ...
            uniform_time, 'linear', 'extrap');
    end
end

fprintf('数据矩阵大小: %d x %d (片段数 x 点数)\n', size(signals_matrix, 1), size(signals_matrix, 2));

%% 数据质量评估
fprintf('\n=== 数据质量评估 ===\n');

quality_scores = zeros(num_valid_segments, 1);

for i = 1:num_valid_segments
    % 获取当前信号
    signal = signals_matrix(i, :);
    
    % 计算信号功率
    signal_power = var(signal);
    
    % 使用差分估计噪声功率
    noise_power = var(diff(signal));
    
    % 计算信噪比(SNR)
    snr_db = 10 * log10(signal_power / (noise_power + eps));
    quality_scores(i) = snr_db;
end

% 排序获取质量排名
[~, quality_rank] = sort(quality_scores, 'descend');

fprintf('质量评估完成\n');
fprintf('最佳片段: #%d (SNR: %.2f dB)\n', quality_rank(1), quality_scores(quality_rank(1)));
fprintf('最差片段: #%d (SNR: %.2f dB)\n', quality_rank(end), quality_scores(quality_rank(end)));
fprintf('平均SNR: %.2f dB\n', mean(quality_scores));

%% 降采样处理
fprintf('\n=== 降采样处理 ===\n');

% 检查是否需要降采样
original_points = length(uniform_time);

if original_points <= CONFIG.DOWNSAMPLE_TARGET_POINTS
    % 无需降采样
    fprintf('原始点数(%d)已小于目标点数(%d)，跳过降采样\n', ...
        original_points, CONFIG.DOWNSAMPLE_TARGET_POINTS);
    
    final_time = uniform_time;
    final_signals = signals_matrix;
    final_sampling_rate = original_points / cleaned_duration;
    
else
    % 执行降采样
    fprintf('执行降采样: %d -> %d 点\n', original_points, CONFIG.DOWNSAMPLE_TARGET_POINTS);
    fprintf('降采样方法: %s\n', CONFIG.DOWNSAMPLE_METHOD);
    
    % 创建降采样时间轴
    final_time = linspace(0, cleaned_duration, CONFIG.DOWNSAMPLE_TARGET_POINTS);
    
    % 初始化降采样后的矩阵
    final_signals = zeros(num_valid_segments, CONFIG.DOWNSAMPLE_TARGET_POINTS);
    
    % 对每个片段进行降采样
    for i = 1:num_valid_segments
        switch CONFIG.DOWNSAMPLE_METHOD
            case 'linear'
                final_signals(i, :) = interp1(uniform_time, signals_matrix(i, :), ...
                    final_time, 'linear', 'extrap');
            case 'pchip'
                final_signals(i, :) = interp1(uniform_time, signals_matrix(i, :), ...
                    final_time, 'pchip', 'extrap');
            case 'spline'
                final_signals(i, :) = interp1(uniform_time, signals_matrix(i, :), ...
                    final_time, 'spline', 'extrap');
            otherwise
                error('未知的降采样方法: %s', CONFIG.DOWNSAMPLE_METHOD);
        end
    end
    
    final_sampling_rate = CONFIG.DOWNSAMPLE_TARGET_POINTS / cleaned_duration;
end

fprintf('最终采样率: %.2f Hz\n', final_sampling_rate);

%% 数据保存
fprintf('\n=== 数据保存 ===\n');

% 生成输出文件名
current_timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-ss');

if is_static_test
    output_filename = sprintf('DAS_Demodulated_%.1fppm_%s.csv', gas_concentration, current_timestamp);
else
    output_filename = sprintf('DAS_Demodulated_Dynamic_%s.csv', current_timestamp);
end

output_filepath = fullfile(folderPath, output_filename);

% 询问用户是否保存
user_response = input('是否保存处理结果? (Y/N) [默认: Y]: ', 's');

% 处理空输入
if isempty(user_response)
    user_response = 'Y';
end

% 执行保存或退出
if strcmpi(user_response, 'Y')
    try
        % 创建数据表
        data_table = table();
        data_table.Time_s = final_time';
        
        % 添加各片段数据
        for i = 1:num_valid_segments
            var_name = sprintf('Segment_%02d', i);
            data_table.(var_name) = final_signals(i, :)';
        end
        
        % 保存为CSV
        writetable(data_table, output_filepath);
        
        % 显示保存成功信息
        fprintf('\n========================================\n');
        fprintf('✅ 数据处理完成！\n');
        fprintf('========================================\n');
        fprintf('保存路径: %s\n', output_filepath);
        fprintf('\n处理摘要:\n');
        fprintf('  测试类型: %s\n', iif(is_static_test, '静态测试', '动态测试'));
        if is_static_test
            fprintf('  气体浓度: %.1f ppm\n', gas_concentration);
        end
        fprintf('  有效片段: %d\n', num_valid_segments);
        fprintf('  信号时长: %.4f s\n', cleaned_duration);
        fprintf('  数据点数: %d\n', length(final_time));
        fprintf('  采样率: %.2f Hz\n', final_sampling_rate);
        fprintf('  最佳SNR: %.2f dB (片段#%d)\n', quality_scores(quality_rank(1)), quality_rank(1));
        fprintf('========================================\n');
        
    catch ME
        error('保存文件时出错: %s', ME.message);
    end
    
elseif strcmpi(user_response, 'N')
    fprintf('\n数据未保存。\n');
    
else
    fprintf('\n输入无效，数据未保存。\n');
end

%% 程序结束
fprintf('\n程序执行完毕。\n');

%% 辅助函数
function result = iif(condition, true_val, false_val)
    % 内联条件函数
    if condition
        result = true_val;
    else
        result = false_val;
    end
end
