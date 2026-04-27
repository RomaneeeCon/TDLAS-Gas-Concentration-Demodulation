% =========================================================================
% TDLAS_Allan_Variance.m
% TDLAS系统Allan方差分析程序
% 
% 作者    : https://github.com/RomaneeeCon
% 版本    : V1.0
% 日期    : 2025-01-18
% 
% 功能描述:
%   本程序用于分析TDLAS系统测量气体浓度的Allan标准差，评估系统的
%   检测极限和最优积分时间。支持DAS和WMS两种测量模式。
% 
% 核心特点:
%   - 支持吸收率或AMP值输入
%   - 自动计算Allan方差和最优积分时间
%   - 双对数坐标可视化
%   - 支持结果导出
% 
% 处理流程:
%   1. 数据导入      - 读取吸收率或AMP分析结果
%   2. 浓度反演      - 根据标定参数计算浓度
%   3. 统计分析      - 计算基本统计量
%   4. Allan计算     - 计算Allan标准差
%   5. 结果可视化    - 绘制Allan偏差曲线
%   6. 数据保存      - 保存分析结果
% 
% 输入:
%   - CSV格式吸收率或AMP分析结果文件
% 
% 输出:
%   - 浓度变化趋势图
%   - Allan标准差曲线
%   - CSV格式分析结果
% 
% 依赖:
%   - MATLAB R2020b或更高版本
%   - Signal Processing Toolbox
% 
% 使用示例:
%   >> TDLAS_Allan_Variance
% 
% 版本历史:
%   V1.0 (2025-01-18) - 初始版本，基于DAS_allan_V2重构
% =========================================================================

%% 程序初始化
clc;                    % 清除命令窗口
close all;              % 关闭所有图形窗口

%% 配置参数
% 测量模式选择
MEASUREMENT_MODE = 'DAS';   % 选项: 'DAS' 或 'WMS'

% 采样周期配置
SAMPLE_PERIOD = 0.2;        % 采样周期 [s]

% 标定参数 (根据实际实验标定结果设置)
CALIBRATION.SLOPE = 0.02671;      % 标定斜率
CALIBRATION.INTERCEPT = 2.01714;  % 标定截距

%% 程序开始
fprintf('========================================\n');
fprintf('    TDLAS Allan方差分析程序\n');
fprintf('    作者: https://github.com/RomaneeeCon\n');
fprintf('========================================\n\n');

fprintf('测量模式: %s\n', MEASUREMENT_MODE);
fprintf('采样周期: %.3f s\n\n', SAMPLE_PERIOD);

%% 数据导入
fprintf('=== 数据导入 ===\n');

% 使用文件对话框选择数据文件
[file_name, folder_path] = uigetfile(...
    {'*.csv', 'CSV Files (*.csv)'; '*.*', 'All Files (*.*)'}, ...
    '选择分析结果文件', ...
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

% 读取CSV数据
data = readtable(file_path);

% 提取数据列
segment_indices = data.SegmentIndex;
absorption_rates = data.PeakAbsorptionPercent;

num_segments = length(absorption_rates);
fprintf('成功导入 %d 组数据\n', num_segments);

%% 标定参数验证
fprintf('\n=== 标定参数 ===\n');
fprintf('斜率: %.6f %%/ppm\n', CALIBRATION.SLOPE);
fprintf('截距: %.6f %%\n', CALIBRATION.INTERCEPT);

% 检查斜率有效性
if CALIBRATION.SLOPE == 0
    error('标定斜率不能为0，请检查参数设置。');
end

%% 浓度反演计算
fprintf('\n=== 浓度反演 ===\n');

% 根据线性标定公式计算浓度
% 浓度(ppm) = (吸收率(%) - 截距) / 斜率
concentration = (absorption_rates - CALIBRATION.INTERCEPT) / CALIBRATION.SLOPE;

% 确保浓度为非负值
concentration = max(concentration, 0);

fprintf('浓度反演完成\n');

%% 统计分析
fprintf('\n=== 统计分析 ===\n');

% 计算基本统计量
conc_mean = mean(concentration);
conc_std = std(concentration);
conc_cv = (conc_std / conc_mean) * 100;  % 变异系数
conc_min = min(concentration);
conc_max = max(concentration);
conc_range = conc_max - conc_min;

fprintf('数据组数: %d\n', num_segments);
fprintf('平均浓度: %.2f ppm\n', conc_mean);
fprintf('标准差: %.2f ppm\n', conc_std);
fprintf('变异系数(CV): %.2f%%\n', conc_cv);
fprintf('最小值: %.2f ppm\n', conc_min);
fprintf('最大值: %.2f ppm\n', conc_max);
fprintf('极差: %.2f ppm\n', conc_range);

%% 浓度变化趋势可视化
figure('Name', '浓度读数变化趋势', 'Position', [200, 200, 1000, 500]);
plot(segment_indices, concentration, 'b-o', 'LineWidth', 1.5, 'MarkerFaceColor', 'b');
hold on;
yline(conc_mean, 'r--', 'LineWidth', 2, 'DisplayName', sprintf('均值=%.2f ppm', conc_mean));

xlabel('信号段序号', 'FontSize', 12);
ylabel('浓度 (ppm)', 'FontSize', 12);
title(sprintf('%s浓度读数变化趋势', MEASUREMENT_MODE), 'FontSize', 14, 'FontWeight', 'bold');
legend('show', 'Location', 'best');
grid on;
hold off;

%% Allan标准差计算
fprintf('\n=== Allan标准差计算 ===\n');

% 计算采样率
fs = 1 / SAMPLE_PERIOD;

% 定义tau值（平均时间窗口长度）
max_tau_seconds = floor(num_segments / 2) * SAMPLE_PERIOD;
tau_seconds = SAMPLE_PERIOD:SAMPLE_PERIOD:max_tau_seconds;

% 将tau转换为样本数
tau_samples = round(tau_seconds / SAMPLE_PERIOD);
tau_samples = unique(tau_samples);
tau_samples = tau_samples(tau_samples > 0);

% 检查数据点是否足够
if length(tau_samples) < 3
    warning('Allan:InsufficientData', '数据点不足，无法计算可靠的Allan标准差。');
    adev = [];
    tau_seconds = [];
    min_adev = NaN;
    tau_at_min = NaN;
else
    % 计算Allan方差
    try
        [avar, ~] = allanvar(concentration, tau_samples, fs);
        adev = sqrt(avar);  % Allan标准差
        
        % 寻找最小Allan标准差
        [min_adev, idx_min] = min(adev);
        tau_at_min = tau_seconds(idx_min);
        
        fprintf('Allan标准差计算成功\n');
        fprintf('最小Allan标准差: %.4f ppm\n', min_adev);
        fprintf('对应最优积分时间: %.2f s\n', tau_at_min);
    catch ME
        warning('Allan:CalculationFailed', 'Allan标准差计算失败: %s', ME.message);
        adev = [];
        tau_seconds = [];
        min_adev = NaN;
        tau_at_min = NaN;
    end
end

%% Allan标准差可视化
if ~isempty(adev) && ~any(isnan(adev))
    figure('Name', 'Allan标准差曲线', 'Position', [300, 300, 800, 600]);
    loglog(tau_seconds, adev, 'b+-', 'LineWidth', 1.5, 'MarkerFaceColor', 'b');
    hold on;
    
    % 标记最小值点
    loglog(tau_at_min, min_adev, 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
    
    % 添加标注
    text(tau_at_min, min_adev, ...
        sprintf(' τ=%.2fs, %.4fppm', tau_at_min, min_adev), ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'bottom', ...
        'FontSize', 10, ...
        'Color', 'red');
    
    title(sprintf('%s Allan标准差 - 浓度稳定性分析', MEASUREMENT_MODE), ...
        'FontSize', 14, 'FontWeight', 'bold');
    xlabel('平均时间 τ (s)', 'FontSize', 12);
    ylabel('Allan标准差 (ppm)', 'FontSize', 12);
    grid on;
    legend('Allan标准差', '最优积分时间', 'Location', 'northeast');
    hold off;
    
    fprintf('Allan标准差曲线已绘制\n');
else
    fprintf('跳过Allan标准差可视化\n');
end

%% 数据保存
fprintf('\n=== 数据保存 ===\n');

user_response = input('是否保存分析结果? (Y/N) [默认: Y]: ', 's');

if isempty(user_response)
    user_response = 'Y';
end

if strcmpi(user_response, 'Y')
    % 生成输出文件名
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    output_file = sprintf('%s_Allan分析_%s.csv', MEASUREMENT_MODE, timestamp);
    
    % 准备保存数据
    data_to_save = [segment_indices, absorption_rates, concentration];
    
    % 使用UTF-8编码打开文件
    fid = fopen(output_file, 'w', 'n', 'UTF-8');
    if fid == -1
        error('无法创建文件: %s', output_file);
    end
    
    % 写入标题行
    fprintf(fid, '段序号,峰值吸收率(%),浓度读数(ppm)\n');
    
    % 写入数据
    fprintf(fid, '%d,%.6f,%.2f\n', data_to_save');
    
    % 如果Allan计算成功，添加统计信息
    if ~isnan(min_adev)
        fprintf(fid, '\nAllan分析统计\n');
        fprintf(fid, '最小Allan标准差(ppm),%.4f\n', min_adev);
        fprintf(fid, '对应积分时间(s),%.2f\n', tau_at_min);
        fprintf(fid, '平均浓度(ppm),%.2f\n', conc_mean);
        fprintf(fid, '标准差(ppm),%.2f\n', conc_std);
        fprintf(fid, '变异系数(%),%.2f\n', conc_cv);
    end
    
    fclose(fid);
    
    fprintf('分析结果已保存至: %s\n', output_file);
    fprintf('文件使用UTF-8编码保存\n');
    
elseif strcmpi(user_response, 'N')
    fprintf('数据未保存\n');
else
    fprintf('输入无效，数据未保存\n');
end

%% 程序结束
fprintf('\n========================================\n');
fprintf('程序执行完毕\n');
fprintf('========================================\n');
