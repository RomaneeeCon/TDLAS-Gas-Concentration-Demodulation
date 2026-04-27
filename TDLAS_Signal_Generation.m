% =========================================================================
% TDLAS_Signal.m
% TDLAS激光器驱动信号生成程序
%
% 作者    : https://github.com/RomaneeeCon
% 版本    : V1.0
% 日期    : 2024-11-19
%
% 功能描述:
%   本程序用于生成TDLAS(可调谐半导体激光吸收光谱)系统所需的激光器
%   驱动信号，包含锯齿波扫描和正弦波调制两种成分的复合信号。
%
% 核心特点:
%   - 生成锯齿波+正弦波复合驱动信号
%   - 支持电流到电压的自动转换
%   - 自动计算并显示电压参数
%   - 自动生成带时间戳的数据文件
%
% 处理流程:
%   1. 参数设置      - 配置采样率、周期、电流参数
%   2. 信号生成      - 计算并生成复合电压信号
%   3. 结果可视化    - 绘制电压和电流波形
%   4. 数据保存      - 自动生成文件名并保存数据
%
% 输入:
%   - 程序内置参数配置
%
% 输出:
%   - TXT格式信号数据文件
%   - 信号波形可视化图形
%
% 依赖:
%   - MATLAB R2020b或更高版本
%
% 使用示例:
%   >> TDLAS_Signal
%
% 版本历史:
%   V1.0 (2024-11-19) - 初始版本
% =========================================================================

%% 1. 初始化与参数设置
% =========================================================================
clc;            % 清空命令行窗口
clear;          % 清除工作区变量
close all;      % 关闭所有已打开的图形窗口

% --- 基本时域参数 ---
fs = 100e3;                     % 采样率
T = 0.2;                        % 信号总周期
t = 0:1/fs:T-1/fs;              % 时间向量

% --- 物理量转换参数 ---
% 1V 的电压对应 30mA 的电流 (I = V * ratio)
current_to_voltage_ratio = 30;  % 

% --- 目标电流波形参数 ---
I_low = 100;                    % 锯齿波低电流
I_high = 110;                   % 锯齿波高电流
I_sin = 3.0;                    % 叠加正弦波电流幅值
duty_cycle = 0.2;               % 信号低电平（0V）占周期的比例
sin_freq = 5000;                % 叠加正弦波的频率

%% 2. 计算并生成信号波形
% =========================================================================

% --- 电流值到电压值的转换 ---
V_low = I_low / current_to_voltage_ratio;     % 锯齿波低电平电压
V_high = I_high / current_to_voltage_ratio;   % 锯齿波高电平电压
V_sin = I_sin / current_to_voltage_ratio;     % 正弦波幅值电压

% --- 输出计算结果供确认 ---
disp('--- 计算得到的电压参数 ---');
disp(['锯齿波低电平电压 V_low:    ', num2str(V_low), ' V']);
disp(['锯齿波高电平电压 V_high:   ', num2str(V_high), ' V']);
disp(['正弦波幅值电压 V_sin:      ', num2str(V_sin), ' V']);

% --- 定义用于文件命名的特殊值 ---
% 注意：这个 V_high_max 是根据您的要求计算并用于文件名的，
% 实际信号的峰值电压是 V_high + V_sin。
V_high_max_for_filename = (V_high + V_sin) / 2;
disp(['用于文件命名的V_high_max: ', num2str(V_high_max_for_filename), ' V']);
disp('-----------------------------------------');

% --- 生成复合电压信号 ---
voltage_signal = zeros(1, length(t)); % 初始化为全0V信号

% 计算各阶段的时间点索引
holdoff_samples = round(duty_cycle * length(t));
ramp_samples = length(t) - holdoff_samples;
ramp_start_index = holdoff_samples + 1;

% 生成斜坡部分的电压
ramp_time_vector = t(ramp_start_index:end);
ramp_voltage = linspace(V_low, V_high, ramp_samples);

% 生成与斜坡同时间、同长度的正弦波电压
sin_voltage = sin(2 * pi * sin_freq * ramp_time_vector) * V_sin;

% 将斜坡和正弦波叠加到信号的对应时间段
voltage_signal(ramp_start_index:end) = ramp_voltage + sin_voltage;

% --- 转换为电流信号 ---
current_signal = voltage_signal * current_to_voltage_ratio;

%% 3. 结果可视化
% =========================================================================

% 绘制电压波形
figure('Name', '信号分析', 'NumberTitle', 'off');
subplot(2, 1, 1);
plot(t, voltage_signal, 'b-', 'LineWidth', 1.5);
title('生成的激光器驱动电压波形');
xlabel('时间');  % 修复：补全引号和括号
ylabel('电压');  % 修复：补全引号和括号
grid on;
xlim([0, T]); % 保证x轴范围正好是一个周期

% 绘制电流波形
subplot(2, 1, 2);
plot(t, current_signal, 'r-', 'LineWidth', 1.5);
title('对应的激光器驱动电流波形');
xlabel('时间');  % 修复：补全引号和括号
ylabel('电流');  % 修复：补全引号和括号
grid on;
xlim([0, T]); % 保证x轴范围正好是一个周期

%% 4. 自动生成文件名并存储数据
% =========================================================================

% --- 生成文件名 ---
% 获取当前时间并格式化为 'yyyyMMdd_HHmmss' 字符串
current_time_str = datestr(now, 'yyyymmdd_HHMM');

% 使用 sprintf 构建规整的文件名，数值保留2位小数
% 格式: signal_data_V_low_V_high_V_sin_sin_freq_V_high_max_time.txt
filename = sprintf('signal_data_%.2f_%.2f_%.2f_%d_%.2f!!_%s.txt', ...
    I_low, I_high, I_sin, sin_freq, V_high_max_for_filename, current_time_str);

% --- 存储数据 ---
% 将时间向量和电压信号组合成两列数据
data_to_save = [t(:), voltage_signal(:)];
% writematrix 函数保存为制表符分隔的文本文件，兼容性好
writematrix(data_to_save, filename, 'Delimiter', '\t');

% 输出确认信息
disp(['信号数据已成功保存到文件: ', filename]);

