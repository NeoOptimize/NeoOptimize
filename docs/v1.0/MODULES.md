# NeoOptimize v1.0 Modules Documentation

## Module Architecture

All modules are located in `/modules/` and follow a consistent pattern:
- Parameter validation
- Logging and reporting
- Rollback capability
- Registry/file backup

### 01_Cleaner.ps1 (205 lines)
**Purpose**: System cleanup and maintenance

**Functions**:
- Remove temporary files (%Temp%)
- Clear browser cache
- Clean up Downloads folder old files
- Remove Windows Update cache
- Clear recycle bin
- Delete prefetch files

**Safety**: Non-critical files only, preserves user data

---

### 02_Performance.ps1 (191 lines)
**Purpose**: System performance optimization

**Functions**:
- Disable visual effects and animations
- Optimize virtual memory
- Clean startup processes
- Disable hibernation
- Optimize disk I/O
- Configure processor scheduling

**Impact**: 10-30% performance improvement reported

---

### 03_Privacy.ps1 (201 lines)
**Purpose**: Privacy and telemetry management

**Functions**:
- Disable Cortana
- Disable app suggestions
- Disable location tracking
- Disable activity history
- Block telemetry services
- Remove diagnostic data

**User Control**: All changes configurable

---

### 04_Network.ps1 (193 lines)
**Purpose**: Network and connectivity optimization

**Functions**:
- Configure DNS servers (Google/Cloudflare)
- Enable hardware offloading
- Optimize TCP stack
- Configure QoS
- Tune MTU size
- Network adapter optimization

**Performance**: Improved bandwidth utilization

---

### 05_Security.ps1 (194 lines)
**Purpose**: Security hardening

**Functions**:
- Configure Windows Defender
- Firewall rule management
- User Account Control settings
- Credential Guard configuration
- BitLocker integration
- Exploit protection tuning

**Backup**: Registry backed up before changes

---

### 06_Services.ps1 (207 lines)
**Purpose**: Service optimization

**Functions**:
- Disable unnecessary Windows services
- Configure service startup types
- Optimize service dependencies
- Manage background tasks
- Clean up redundant services
- Log all changes

**Rollback**: Full service restoration available

---

### 07_Updates.ps1 (267 lines)
**Purpose**: Windows Update management

**Functions**:
- Configure update policies
- Schedule automatic updates
- Manage driver updates
- Update history management
- Notification customization
- Update log analysis

**Control**: Flexible update scheduling

---

### 08_Power.ps1 (227 lines)
**Purpose**: Power and thermal management

**Functions**:
- Power plan optimization
- CPU power state control
- Thermal management
- Battery optimization (laptops)
- Screen timeout settings
- Sleep and hibernation configuration

**Efficiency**: Extended battery life on laptops

---

## Common.ps1 Library (567 lines)

Provides shared utilities for all modules:

### UI Functions
- Color ANSI output with branding
- Menu systems and prompts
- Progress indicators
- Logging infrastructure

### System Functions
- Registry operations
- File backup/restore
- Service management
- Event log querying

### Safety Functions
- Restore point creation
- Rollback management
- Permission elevation
- Error handling

---

## Module Execution Order

The main launcher automatically executes modules in this order:
1. System backup (restore points, registry)
2. Cleaner (remove old files first)
3. Performance (tune system)
4. Privacy (configure telemetry)
5. Network (optimize connectivity)
6. Security (apply hardening)
7. Services (disable unnecessary)
8. Updates (configure Windows Update)
9. Power (tune power/thermal)

This order ensures:
- Dependencies are met
- Backup happens first
- Non-destructive operations first
- Security operations before system tuning

