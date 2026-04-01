# Contributing to AudioIntelligence

Thank you for your interest in improving **AudioIntelligence**! We welcome contributions from everyone.

## Getting Started

1.  **Fork the repository** on GitHub.
2.  **Clone your fork** locally:
    ```bash
    git clone https://github.com/YOUR_USERNAME/audiointelligence.git
    ```
3.  **Create a new branch** for your feature or bugfix:
    ```bash
    git checkout -b feature/your-feature-name
    ```
4.  **Make your changes**. Ensure your code follows the established style and includes appropriate tests.

## Coding Standards

- Follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).
- Use `async/await` for asynchronous operations.
- Prefer `vDSP` and `Accelerate` for DSP tasks to maintain Apple Silicon optimization.
- Document public APIs using triple-slash (`///`) comments.

## Submitting Changes

1.  **Run tests** to ensure no regressions:
    ```bash
    swift test
    ```
2.  **Commit your changes** with a descriptive message:
    ```bash
    git commit -m "feat: add support for local pulse analysis"
    ```
3.  **Push to your fork**:
    ```bash
    git push origin feature/your-feature-name
    ```
4.  **Open a Pull Request** against the `main` branch of the original repository.

## Reporting Issues

Use the GitHub Issues tracker to report bugs or suggest features. Be as descriptive as possible, including steps to reproduce bugs and snippets of expected behavior for feature requests.

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

---

Happy coding! 🎙️
