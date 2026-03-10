# Contributing to Neo Optimize AI

Thank you for your interest in contributing to Neo Optimize AI! This document provides guidelines and instructions for contributing.

## 📋 Table of Contents

- [Code of Conduct](#-code-of-conduct)
- [Getting Started](#-getting-started)
- [Development Setup](#-development-setup)
- [Making Changes](#-making-changes)
- [Submitting Changes](#-submitting-changes)
- [Coding Standards](#-coding-standards)
- [Testing](#-testing)
- [Documentation](#-documentation)
- [Reporting Bugs](#-reporting-bugs)
- [Requesting Features](#-requesting-features)

---

## 🤝 Code of Conduct

Please be respectful and constructive in all interactions. We are committed to providing a welcoming and inclusive environment for all contributions.

### Respectful Communication
- Be kind and respectful in code reviews and discussions
- Assume good intentions from other contributors
- Welcome feedback and different perspectives

---

## 🚀 Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally
3. **Create a feature branch** for your work
4. **Make your changes** following our guidelines
5. **Test thoroughly** before submitting
6. **Submit a Pull Request** with clear description

---

## 💻 Development Setup

### Prerequisites
- Windows 10/11/12
- Python 3.10+
- Git

### Setup Instructions

```bash
# 1. Clone your fork
git clone https://github.com/YOUR_USERNAME/NeoOptimize.git
cd NeoOptimize

# 2. Create virtual environment
python -m venv venv
venv\Scripts\activate

# 3. Install dependencies
cd backend
pip install -r requirements-neoai.txt

# 4. Create .env file
copy .env.example .env
# Edit .env with your configurations

# 5. Test the backend
python neoai_backend.py
# Should show: Application startup complete

# 6. Test the UI (new terminal)
python gradio_ui.py
# Should show: Running on http://0.0.0.0:7861
```

---

## 📝 Making Changes

### Branch Naming
Use descriptive branch names:
```
feature/add-new-tool
fix/api-key-validation
docs/improve-readme
test/add-unit-tests
```

### Commit Messages
- Use clear, descriptive commit messages
- Start with a verb: "Add", "Fix", "Improve", "Refactor", "Document"
- Keep first line under 72 characters
- Provide detailed description in body

**Example:**
```
Add remove_bloatware cleaning tool

- Removes 15+ common bloatware applications
- Supports dry-run mode for safety
- Logs all removed packages
- Includes comprehensive error handling
```

### Code Style

#### Python
- Follow [PEP 8](https://www.python.org/dev/peps/pep-0008/)
- Use 4 spaces for indentation
- Maximum line length: 100 characters
- Use type hints where possible
- Include docstrings for all functions

**Example:**
```python
def clean_temp_files(dry_run: bool = True) -> str:
    """
    Clean temporary files from system.
    
    Args:
        dry_run (bool): Preview changes without executing
        
    Returns:
        str: Summary of operation
    """
    # Implementation
    pass
```

#### File Organization
```
neoai/
├── backend/
│   ├── neoai_backend.py      # Main FastAPI server
│   ├── gradio_ui.py           # Web interface
│   ├── windows_cmd_executor.py # Windows integration
│   └── integration_module.py   # Integration generators
├── docs/
│   ├── README.md
│   ├── QUICKSTART.md
│   └── ...
└── tests/
    ├── test_backend.py
    └── test_tools.py
```

---

## 🔄 Submitting Changes

### Before Submitting

1. **Test your changes**
   ```bash
   # Test individual tools
   python -c "from neoai_backend import clean_temp_files; print(clean_temp_files())"
   
   # Test API endpoints
   curl http://localhost:7860/health
   
   # Test UI in browser
   ```

2. **Update documentation** if needed
   - Update README.md for user-facing changes
   - Update docstrings for code changes
   - Update CHANGELOG.md with new features

3. **Run the test suite**
   ```bash
   python -m pytest tests/ -v
   ```

### Creating a Pull Request

1. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

2. **Create PR on GitHub**
   - Use clear title and description
   - Reference any related issues (#123)
   - Screenshots for UI changes
   - Explain why this change is needed

3. **PR Template**
   ```markdown
   ## Description
   Brief description of changes
   
   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Documentation update
   
   ## How to Test
   Steps to verify the changes
   
   ## Checklist
   - [ ] Code follows style guidelines
   - [ ] Documentation is updated
   - [ ] Tests pass
   - [ ] No breaking changes
   ```

---

## ✅ Testing

### Unit Tests
```bash
# Run all tests
python -m pytest tests/ -v

# Run specific test file
python -m pytest tests/test_tools.py -v

# Run specific test
python -m pytest tests/test_tools.py::test_clean_temp -v
```

### Integration Tests
```bash
# Test backend startup
python neoai_backend.py &
sleep 2
curl http://localhost:7860/health

# Test API endpoints
curl -H "X-API-Key: dev_key" http://localhost:7860/system-info

# Test UI
python gradio_ui.py
# Open browser and test each tab
```

### Manual Testing
- Test dry-run mode for all tools
- Test error handling (e.g., invalid paths)
- Test with limited disk space
- Test on different Windows versions
- Test with various API keys

---

## 📚 Documentation

### Update README
If adding new features, update:
- Main `README.md` with feature description
- `docs/QUICKSTART.md` if it's a common operation
- `docs/README.md` for technical details
- API docs in code comments

### Code Documentation
```python
def new_tool(parameter: str, dry_run: bool = True) -> str:
    """
    Tool description in one line.
    
    Longer description explaining what the tool does,
    why it's useful, and any important details.
    
    Args:
        parameter (str): Description of parameter
        dry_run (bool): Preview changes if True
        
    Returns:
        str: Summary of operation
        
    Raises:
        Exception: Description of when exception occurs
        
    Example:
        >>> result = new_tool("C:", dry_run=True)
        >>> print(result)
        [DRY-RUN] Operation summary
    """
    # Implementation
    pass
```

---

## 🐛 Reporting Bugs

### Before Reporting
1. Check [existing issues](https://github.com/NeoOptimize/NeoOptimize/issues)
2. Check [FAQ](./docs/FAQ.md)
3. Check [Troubleshooting](./docs/TROUBLESHOOTING.md)

### Report Template
```markdown
## Bug Description
Clear description of the issue

## Steps to Reproduce
1. Step one
2. Step two
3. Expected vs actual result

## Environment
- Windows Version: 10/11/12
- Python Version: 3.x.x
- Neo Optimize Version: 1.0.0

## Error Log
```
Paste error output
```

## Screenshots
If applicable, add screenshots

## Possible Fix
If you have ideas about what might be causing this
```

---

## 💡 Requesting Features

### Feature Request Template
```markdown
## Description
Clear description of desired feature

## Use Case
Why this feature is needed and who would use it

## Proposed Solution
How you envision the feature working

## Alternatives Considered
Other approaches you've thought about

## Additional Context
Any other relevant information
```

### Feature Evaluation Criteria
- **Usefulness:** How many users would benefit?
- **Effort:** How complex is implementation?
- **Maintenance:** After release, is it easy to maintain?
- **Safety:** Doesn't break existing functionality?
- **Consistency:** Fits with project philosophy?

---

## 🎯 Areas for Contribution

### High Priority
- 🐛 Bug fixes
- 📚 Documentation improvements
- ✅ Unit tests
- 🌍 Translations

### Medium Priority
- ✨ Minor feature enhancements
- 🎨 UI/UX improvements
- 📝 Example code and tutorials
- 🔍 Code optimization

### Roadmap Items
- 🚀 Docker containerization
- 🖥️ macOS support
- 🐧 Linux support
- 📱 Mobile companion app
- 🔄 Cloud synchronization

---

## 📞 Getting Help

- **Questions:** Open [Discussion](https://github.com/NeoOptimize/NeoOptimize/discussions)
- **Bugs:** Open [Issue](https://github.com/NeoOptimize/NeoOptimize/issues)
- **Chat:** [GitHub Discussions](https://github.com/NeoOptimize/NeoOptimize/discussions)
- **Email:** Open an issue and we'll reach out

---

## 🎓 Learning Resources

- [Git Basics](https://git-scm.com/doc)
- [GitHub Flow](https://guides.github.com/introduction/flow/)
- [PEP 8 Style Guide](https://www.python.org/dev/peps/pep-0008/)
- [Python Testing](https://docs.python.org/3/library/unittest.html)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)

---

## 🎉 Recognition

Contributors will be recognized in:
- GitHub Contributors page
- [CONTRIBUTORS.md](./CONTRIBUTORS.md) file
- Release notes for major contributions

---

## 📞 Questions?

If you have any questions about contributing:
1. Check [FAQ](./docs/FAQ.md)
2. Open [Discussion](https://github.com/NeoOptimize/NeoOptimize/discussions)
3. Open [Issue](https://github.com/NeoOptimize/NeoOptimize/issues) with label `question`

---

<div align="center">

**Thank you for contributing to Neo Optimize AI! 🙏**

Your contributions make this project better for everyone.

</div>
