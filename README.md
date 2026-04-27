# TDLAS-Gas-Concentration-Demodulation

A comprehensive MATLAB toolbox for Tunable Diode Laser Absorption Spectroscopy (TDLAS) signal processing and gas concentration retrieval.

[![MATLAB](https://img.shields.io/badge/MATLAB-R2020b%2B-blue)](https://www.mathworks.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Author:** [RomaneeeCon](https://github.com/RomaneeeCon)

---

## Features

- **DAS (Direct Absorption Spectroscopy)** demodulation with dual-threshold detection
- **WMS (Wavelength Modulation Spectroscopy)** 2F harmonic extraction with phase correction
- **Multi-channel WMS** support (CO₂/N₂O/CO simultaneous detection)
- **Allan variance analysis** for detection limit evaluation
- **Signal generation** for laser driver waveform synthesis

Designed for atmospheric monitoring, industrial process control, and environmental sensing applications.

---

## Project Structure

```
TDLAS-Demodulation-Algorithms/
├── src/
│   └── matlab/
│       ├── TDLAS_DAS_Demodulation.m          # DAS demodulation
│       ├── TDLAS_WMS_Demodulation.m          # WMS demodulation
│       ├── TDLAS_WMS_MultiChannel.m          # Multi-channel WMS
│       ├── TDLAS_Allan_Variance.m            # Allan variance analysis
│       └── TDLAS_Signal_Generation.m         # Signal generation
├── .gitignore
├── LICENSE
└── README.md
```

---

## Module Descriptions

### 1. DAS Demodulation (`TDLAS_DAS_Demodulation.m`)

Main DAS signal demodulation program with static/dynamic test modes.

**Key Features:**
- Signal segmentation and extraction
- Noise filtering and denoising
- Concentration inversion calculation
- Downsampling processing

**Highlights:**
- Preserves absolute signal amplitude throughout processing
- Automatic valid signal segment extraction via dual-threshold detection
- Support for signal alignment, cleaning, and downsampling

### 2. WMS Demodulation (`TDLAS_WMS_Demodulation.m`)

Main WMS signal demodulation with lock-in amplification.

**Key Features:**
- Second harmonic (2F) signal extraction
- Automatic phase correction
- Feature point extraction (MAX, leftMIN, rightMIN)
- AMP amplitude calculation

**Highlights:**
- Support for TXT and CSV dual-format data import
- Automatic phase correction for signal consistency
- Automated feature extraction

### 3. Multi-Channel WMS (`TDLAS_WMS_MultiChannel.m`)

Triple-channel WMS processing for CO₂/N₂O/CO simultaneous detection.

**Key Features:**
- Simultaneous demodulation of three gases at different frequencies (2kHz/3kHz/5kHz)
- Independent phase correction for each channel
- DC baseline extraction and normalization
- Comprehensive visualization and data export

### 4. Allan Variance Analysis (`TDLAS_Allan_Variance.m`)

Allan standard deviation analysis for detection limit evaluation.

**Key Features:**
- Concentration stability assessment
- Optimal integration time calculation
- Noise characteristic analysis

**Highlights:**
- Support for absorbance or AMP value input
- Automatic Allan variance and optimal integration time calculation
- Log-log coordinate visualization

### 5. Signal Generation (`TDLAS_Signal_Generation.m`)

TDLAS laser driver signal generation (sawtooth + sine wave composite signal).

**Key Features:**
- Generate sawtooth scan + sine wave modulation composite signal
- Automatic current-to-voltage conversion
- Automatic parameter calculation and display
- Auto-generated timestamped data files

---

## Quick Start

### MATLAB Usage

1. Open MATLAB and navigate to the project directory
2. Run the desired script based on your experiment type:

```matlab
% DAS demodulation
run('src/matlab/TDLAS_DAS_Demodulation.m')

% WMS demodulation
run('src/matlab/TDLAS_WMS_Demodulation.m')

% Multi-channel WMS
run('src/matlab/TDLAS_WMS_MultiChannel.m')

% Allan variance analysis
run('src/matlab/TDLAS_Allan_Variance.m')

% Signal generation
run('src/matlab/TDLAS_Signal_Generation.m')
```

---

## System Requirements

### MATLAB
- MATLAB R2020b or higher
- Signal Processing Toolbox
- Statistics and Machine Learning Toolbox (recommended)

---

## Code Standards

All MATLAB code follows these conventions:

1. **File header comments**: Include function description, author info, version history
2. **Author attribution**: `https://github.com/RomaneeeCon`
3. **Code segmentation**: Use `%%` to separate functional modules
4. **Chinese comments**: All comments are in Chinese
5. **Variable naming**: Meaningful variable names, avoid single-letter variables

---

## Version History

| Version | Date | Description |
|---------|------|-------------|
| V1.0 | 2025-01 | Initial release with standardized code structure |

---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Acknowledgments

Thanks to all lab colleagues for their support and assistance.(https://cheng.tju.edu.cn/en.htm)

---

## Contact

For questions or suggestions, please contact: [RomaneeeCon](https://github.com/RomaneeeCon)
