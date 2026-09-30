"""Deep Codebase Reviewer and Static Analysis Suite.

This module performs comprehensive static code analysis, structural inspection,
maintainability assessment, security scanning, and quality metrics evaluation
across the codebase using Python's standard library.
"""

from __future__ import annotations

import ast
import json
import os
import re
import sys
import tokenize
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple


@dataclass
class CodeIssue:
    """Represents a single issue or code smell identified during review."""

    file_path: str
    line: int
    column: int
    rule_id: str
    category: str
    severity: str  # 'INFO', 'WARNING', 'ERROR', 'CRITICAL'
    message: str
    suggestion: Optional[str] = None


@dataclass
class FunctionMetrics:
    """Metrics calculated for a function or method."""

    name: str
    line_start: int
    line_end: int
    arg_count: int
    cyclomatic_complexity: int
    has_docstring: bool
    has_type_annotations: bool
    is_async: bool


@dataclass
class ClassMetrics:
    """Metrics calculated for a class definition."""

    name: str
    line_start: int
    line_end: int
    method_count: int
    base_classes: List[str]
    has_docstring: bool


@dataclass
class FileReport:
    """Comprehensive analysis report for an individual file."""

    file_path: str
    total_lines: int
    code_lines: int
    comment_lines: int
    blank_lines: int
    docstring_lines: int
    cyclomatic_complexity: int
    maintainability_index: float
    classes: List[ClassMetrics] = field(default_factory=list)
    functions: List[FunctionMetrics] = field(default_factory=list)
    issues: List[CodeIssue] = field(default_factory=list)


@dataclass
class CodebaseReport:
    """Summary and aggregated report for the entire inspected codebase."""

    root_directory: str
    scanned_files_count: int
    total_lines: int
    total_code_lines: int
    total_comments: int
    average_maintainability: float
    total_issues_by_severity: Dict[str, int] = field(
        default_factory=lambda: {"INFO": 0, "WARNING": 0, "ERROR": 0, "CRITICAL": 0}
    )
    files: List[FileReport] = field(default_factory=list)


class ASTComplexityVisitor(ast.NodeVisitor):
    """Calculates McCabe Cyclomatic Complexity for AST blocks."""

    def __init__(self) -> None:
        self.complexity: int = 1

    def visit_If(self, node: ast.If) -> None:
        self.complexity += 1
        self.generic_visit(node)

    def visit_For(self, node: ast.For) -> None:
        self.complexity += 1
        self.generic_visit(node)

    def visit_AsyncFor(self, node: ast.AsyncFor) -> None:
        self.complexity += 1
        self.generic_visit(node)

    def visit_While(self, node: ast.While) -> None:
        self.complexity += 1
        self.generic_visit(node)

    def visit_ExceptHandler(self, node: ast.ExceptHandler) -> None:
        self.complexity += 1
        self.generic_visit(node)

    def visit_With(self, node: ast.With) -> None:
        self.complexity += 1
        self.generic_visit(node)

    def visit_AsyncWith(self, node: ast.AsyncWith) -> None:
        self.complexity += 1
        self.generic_visit(node)

    def visit_BoolOp(self, node: ast.BoolOp) -> None:
        self.complexity += len(node.values) - 1
        self.generic_visit(node)

    def visit_Try(self, node: ast.Try) -> None:
        self.generic_visit(node)

    def visit_Match(self, node: Any) -> None:
        # Python 3.10+ pattern matching
        if hasattr(node, "cases"):
            self.complexity += len(node.cases)
        self.generic_visit(node)


class CodeReviewer:
    """Performs static checks, code smell detection, and security auditing."""

    DANGEROUS_CALLS: Set[str] = {"eval", "exec", "compile"}
    SHELL_EXEC_MODULES: Set[str] = {"subprocess", "os"}

    def __init__(self, root_path: str = ".") -> None:
        self.root_path = Path(root_path).resolve()

    def review_codebase(
        self, exclude_patterns: Optional[List[str]] = None
    ) -> CodebaseReport:
        """Scan target codebase directory recursively and build comprehensive report."""
        if exclude_patterns is None:
            exclude_patterns = [
                ".git",
                "__pycache__",
                ".venv",
                "venv",
                "env",
                ".mypy_cache",
                ".pytest_cache",
                "dist",
                "build",
            ]

        target_files: List[Path] = []
        for path in self.root_path.rglob("*.py"):
            parts = set(path.parts)
            if any(pat in parts for pat in exclude_patterns):
                continue
            target_files.append(path)

        files_report: List[FileReport] = []
        total_loc = 0
        total_cloc = 0
        total_comments = 0
        severity_counts = {"INFO": 0, "WARNING": 0, "ERROR": 0, "CRITICAL": 0}
        total_mi = 0.0

        for file_path in target_files:
            report = self.review_file(file_path)
            files_report.append(report)
            total_loc += report.total_lines
            total_cloc += report.code_lines
            total_comments += report.comment_lines
            total_mi += report.maintainability_index

            for issue in report.issues:
                severity = issue.severity.upper()
                severity_counts[severity] = severity_counts.get(severity, 0) + 1

        avg_mi = total_mi / len(files_report) if files_report else 100.0

        return CodebaseReport(
            root_directory=str(self.root_path),
            scanned_files_count=len(files_report),
            total_lines=total_loc,
            total_code_lines=total_cloc,
            total_comments=total_comments,
            average_maintainability=round(avg_mi, 2),
            total_issues_by_severity=severity_counts,
            files=files_report,
        )

    def review_file(self, file_path: Path) -> FileReport:
        """Examine a single python file and extract metrics & defects."""
        relative_name = str(file_path.relative_to(self.root_path))
        try:
            with tokenize.open(file_path) as f:
                content = f.read()
        except (OSError, SyntaxError, UnicodeDecodeError) as err:
            return FileReport(
                file_path=relative_name,
                total_lines=0,
                code_lines=0,
                comment_lines=0,
                blank_lines=0,
                docstring_lines=0,
                cyclomatic_complexity=0,
                maintainability_index=0.0,
                issues=[
                    CodeIssue(
                        file_path=relative_name,
                        line=1,
                        column=1,
                        rule_id="E0001",
                        category="Syntax/IO",
                        severity="CRITICAL",
                        message=f"Cannot open or decode file: {err}",
                    )
                ],
            )

        line_metrics = self._calculate_line_metrics(file_path, content)
        parsed_ast: Optional[ast.AST] = None
        issues: List[CodeIssue] = []

        try:
            parsed_ast = ast.parse(content, filename=str(file_path))
        except SyntaxError as syntax_err:
            issues.append(
                CodeIssue(
                    file_path=relative_name,
                    line=syntax_err.lineno or 1,
                    column=syntax_err.offset or 1,
                    rule_id="E0002",
                    category="Syntax",
                    severity="CRITICAL",
                    message=f"Syntax Error: {syntax_err.msg}",
                    suggestion="Fix Python syntax syntax according to PEP 8 / current interpreter standard.",
                )
            )

        classes: List[ClassMetrics] = []
        functions: List[FunctionMetrics] = []
        total_cc = 1

        if parsed_ast is not None:
            total_cc = self._calculate_node_complexity(parsed_ast)
            classes, functions = self._inspect_ast_definitions(parsed_ast)
            ast_issues = self._audit_ast_nodes(parsed_ast, relative_name)
            issues.extend(ast_issues)

        # Style & pattern checks on lines
        issues.extend(self._audit_raw_lines(content, relative_name))

        # Maintainability Index approximation
        mi = self._calculate_maintainability_index(
            lines=line_metrics["total_lines"],
            complexity=total_cc,
            comment_ratio=(
                line_metrics["comment_lines"] / max(line_metrics["total_lines"], 1)
            ),
        )

        return FileReport(
            file_path=relative_name,
            total_lines=line_metrics["total_lines"],
            code_lines=line_metrics["code_lines"],
            comment_lines=line_metrics["comment_lines"],
            blank_lines=line_metrics["blank_lines"],
            docstring_lines=line_metrics["docstring_lines"],
            cyclomatic_complexity=total_cc,
            maintainability_index=mi,
            classes=classes,
            functions=functions,
            issues=issues,
        )

    def _calculate_line_metrics(
        self, file_path: Path, content: str
    ) -> Dict[str, int]:
        """Compute SLOC, blank lines, comments, and docstring metrics."""
        lines = content.splitlines()
        total_lines = len(lines)
        blank_lines = sum(1 for line in lines if not line.strip())

        comment_lines = 0
        docstring_lines = 0

        try:
            with open(file_path, "rb") as bf:
                tokens = list(tokenize.tokenize(bf.readline))
                for tok in tokens:
                    if tok.type == tokenize.COMMENT:
                        comment_lines += 1
                    elif tok.type == tokenize.STRING:
                        # Check if token is likely a docstring
                        start_line, _ = tok.start
                        end_line, _ = tok.end
                        span = end_line - start_line + 1
                        if span > 0 and tok.string.startswith(('"""', "'''")):
                            docstring_lines += span
        except Exception:
            # Fallback estimation
            comment_lines = sum(
                1 for line in lines if line.strip().startswith("#")
            )

        code_lines = max(0, total_lines - blank_lines - comment_lines)

        return {
            "total_lines": total_lines,
            "code_lines": code_lines,
            "comment_lines": comment_lines,
            "blank_lines": blank_lines,
            "docstring_lines": docstring_lines,
        }

    def _calculate_node_complexity(self, node: ast.AST) -> int:
        """Calculate cyclomatic complexity of an AST node."""
        visitor = ASTComplexityVisitor()
        visitor.visit(node)
        return visitor.complexity

    def _calculate_maintainability_index(
        self, lines: int, complexity: int, comment_ratio: float
    ) -> float:
        """Simplified Maintainability Index calculation on 0-100 scale."""
        import math

        if lines <= 0:
            return 100.0

        volume = lines * math.log2(max(lines, 2))
        raw_mi = (
            171.0
            - 5.2 * math.log(max(volume, 1.0))
            - 0.23 * complexity
            - 16.2 * math.log(max(lines, 1.0))
            + 50.0 * math.sin(math.sqrt(2.4 * max(comment_ratio, 0.0)))
        )
        normalized_mi = max(0.0, min(100.0, (raw_mi * 100.0) / 171.0))
        return round(normalized_mi, 2)

    def _inspect_ast_definitions(
        self, root_node: ast.AST
    ) -> Tuple[List[ClassMetrics], List[FunctionMetrics]]:
        """Extract metadata for classes and functions."""
        classes: List[ClassMetrics] = []
        functions: List[FunctionMetrics] = []

        for node in ast.walk(root_node):
            if isinstance(node, ast.ClassDef):
                base_names = []
                for base in node.bases:
                    if isinstance(base, ast.Name):
                        base_names.append(base.id)
                    elif isinstance(base, ast.Attribute):
                        base_names.append(f"{ast.unparse(base.value)}.{base.attr}")
                    else:
                        base_names.append("complex_base")

                method_count = sum(
                    1
                    for item in node.body
                    if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef))
                )
                classes.append(
                    ClassMetrics(
                        name=node.name,
                        line_start=node.lineno,
                        line_end=getattr(node, "end_lineno", node.lineno),
                        method_count=method_count,
                        base_classes=base_names,
                        has_docstring=ast.get_docstring(node) is not None,
                    )
                )

            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                cc = self._calculate_node_complexity(node)
                total_args = (
                    len(node.args.args)
                    + len(node.args.kwonlyargs)
                    + (1 if node.args.vararg else 0)
                    + (1 if node.args.kwarg else 0)
                )

                has_annotations = node.returns is not None or any(
                    arg.annotation is not None for arg in node.args.args
                )

                functions.append(
                    FunctionMetrics(
                        name=node.name,
                        line_start=node.lineno,
                        line_end=getattr(node, "end_lineno", node.lineno),
                        arg_count=total_args,
                        cyclomatic_complexity=cc,
                        has_docstring=ast.get_docstring(node) is not None,
                        has_type_annotations=has_annotations,
                        is_async=isinstance(node, ast.AsyncFunctionDef),
                    )
                )

        return classes, functions

    def _audit_ast_nodes(
        self, root_node: ast.AST, file_path: str
    ) -> List[CodeIssue]:
        """Perform static analysis rules over the AST."""
        issues: List[CodeIssue] = []

        for node in ast.walk(root_node):
            # Check 1: eval / exec / dangerous calls
            if isinstance(node, ast.Call):
                func_name = ""
                if isinstance(node.func, ast.Name):
                    func_name = node.func.id
                elif isinstance(node.func, ast.Attribute):
                    func_name = node.func.attr

                if func_name in self.DANGEROUS_CALLS:
                    issues.append(
                        CodeIssue(
                            file_path=file_path,
                            line=node.lineno,
                            column=node.col_offset,
                            rule_id="SEC001",
                            category="Security",
                            severity="CRITICAL",
                            message=f"Dangerous dynamic execution call '{func_name}()' detected.",
                            suggestion="Avoid dynamic execution; use dedicated safe parsing, mapping, or serialization.",
                        )
                    )

                if (
                    func_name == "Popen"
                    or func_name == "system"
                    or func_name == "call"
                ):
                    for keyword in node.keywords:
                        if keyword.arg == "shell" and getattr(
                            keyword.value, "value", False
                        ) is True:
                            issues.append(
                                CodeIssue(
                                    file_path=file_path,
                                    line=node.lineno,
                                    column=node.col_offset,
                                    rule_id="SEC002",
                                    category="Security",
                                    severity="CRITICAL",
                                    message="Subprocess execution with shell=True is susceptible to injection.",
                                    suggestion="Pass arguments as a sequence list and set shell=False.",
                                )
                            )

            # Check 2: Bare except
            elif isinstance(node, ast.ExceptHandler):
                if node.type is None:
                    issues.append(
                        CodeIssue(
                            file_path=file_path,
                            line=node.lineno,
                            column=node.col_offset,
                            rule_id="ERR001",
                            category="Reliability",
                            severity="WARNING",
                            message="Bare 'except:' catches BaseException (including KeyboardInterrupt and SystemExit).",
                            suggestion="Catch specific exception types, e.g. 'except Exception:' or domain-specific exceptions.",
                        )
                    )

            # Check 3: Mutable default argument
            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                for default in node.args.defaults + node.args.kw_defaults:
                    if default is not None and isinstance(
                        default, (ast.List, ast.Dict, ast.Set)
                    ):
                        issues.append(
                            CodeIssue(
                                file_path=file_path,
                                line=default.lineno,
                                column=default.col_offset,
                                rule_id="PERF001",
                                category="Bug Risk",
                                severity="ERROR",
                                message=f"Function '{node.name}' uses mutable default argument.",
                                suggestion="Use None as default and assign a new instance inside the body.",
                            )
                        )

                # High cyclomatic complexity per function
                fn_cc = self._calculate_node_complexity(node)
                if fn_cc > 10:
                    issues.append(
                        CodeIssue(
                            file_path=file_path,
                            line=node.lineno,
                            column=node.col_offset,
                            rule_id="COMP001",
                            category="Complexity",
                            severity="WARNING",
                            message=f"Function '{node.name}' has high cyclomatic complexity ({fn_cc} > 10).",
                            suggestion="Decompose function into smaller, single-purpose helper functions.",
                        )
                    )

                # High parameter count
                param_count = (
                    len(node.args.args)
                    + len(node.args.kwonlyargs)
                    + (1 if node.args.vararg else 0)
                    + (1 if node.args.kwarg else 0)
                )
                if param_count > 6 and node.name != "__init__":
                    issues.append(
                        CodeIssue(
                            file_path=file_path,
                            line=node.lineno,
                            column=node.col_offset,
                            rule_id="DSGN001",
                            category="Design",
                            severity="INFO",
                            message=f"Function '{node.name}' has {param_count} parameters (exceeds recommended 6).",
                            suggestion="Group related parameters into a dataclass or configuration object.",
                        )
                    )

        return issues

    def _audit_raw_lines(
        self, content: str, file_path: str
    ) -> List[CodeIssue]:
        """Perform text-level checks on line length, hardcoded credentials, and TODOs."""
        issues: List[CodeIssue] = []
        lines = content.splitlines()

        secret_regex = re.compile(
            r"(?i)(api[_-]?key|secret|password|access[_-]?token)\s*=\s*['\"][a-zA-Z0-9_\-\.]{8,}['\"]"
        )
        todo_regex = re.compile(r"#\s*(TODO|FIXME|XXX|BUG):?", re.IGNORECASE)

        for idx, line in enumerate(lines, start=1):
            # Line length check (> 120 chars)
            if len(line) > 120:
                issues.append(
                    CodeIssue(
                        file_path=file_path,
                        line=idx,
                        column=120,
                        rule_id="FMT001",
                        category="Formatting",
                        severity="INFO",
                        message=f"Line exceeds 120 characters ({len(line)} chars).",
                        suggestion="Break line to adhere to PEP 8 line length limits.",
                    )
                )

            # Potential hardcoded secret
            if secret_regex.search(line):
                issues.append(
                    CodeIssue(
                        file_path=file_path,
                        line=idx,
                        column=1,
                        rule_id="SEC003",
                        category="Security",
                        severity="WARNING",
                        message="Potential hardcoded secret or credential detected.",
                        suggestion="Extract credentials to environment variables or secret store.",
                    )
                )

            # Pending debt marker
            match_todo = todo_regex.search(line)
            if match_todo:
                issues.append(
                    CodeIssue(
                        file_path=file_path,
                        line=idx,
                        column=match_todo.start() + 1,
                        rule_id="DEBT001",
                        category="Technical Debt",
                        severity="INFO",
                        message=f"Found outstanding tag: {line.strip()}",
                        suggestion="Resolve the action item or convert it into a tracked issue.",
                    )
                )

        return issues


class ReviewReporter:
    """Formats and prints deep review results in human-readable and machine formats."""

    @staticmethod
    def render_cli(report: CodebaseReport) -> None:
        """Print formatted terminal report."""
        divider = "=" * 80
        sub_divider = "-" * 80

        print("\n" + divider)
        print("          DEEP CODEBASE AUDIT & ARCHITECTURAL REVIEW REPORT          ")
        print(divider)
        print(f"Target Directory         : {report.root_directory}")
        print(f"Total Python Files       : {report.scanned_files_count}")
        print(f"Total Lines of Code      : {report.total_lines} (Logical SLOC: {report.total_code_lines})")
        print(f"Total Comment Lines      : {report.total_comments}")
        print(f"Average Maintainability  : {report.average_maintainability} / 100")
        print(
            "Issues Summary           : "
            + " | ".join(f"{k}: {v}" for k, v in report.total_issues_by_severity.items())
        )
        print(divider + "\n")

        # Per-file breakdown
        print("FILE-BY-FILE ANALYSIS:")
        print(sub_divider)

        for file_rep in report.files:
            status_symbol = "✓" if not file_rep.issues else "!"
            print(
                f"[{status_symbol}] {file_rep.file_path:<45} | "
                f"Lines: {file_rep.total_lines:<5} | "
                f"MI: {file_rep.maintainability_index:<5} | "
                f"Complexity: {file_rep.cyclomatic_complexity:<3} | "
                f"Issues: {len(file_rep.issues)}"
            )

            # Print functions & classes info if any high complexity
            for fn in file_rep.functions:
                if fn.cyclomatic_complexity > 8 or fn.arg_count > 5:
                    print(
                        f"    ↳ Function '{fn.name}' (L{fn.line_start}-L{fn.line_end}) -> "
                        f"CC: {fn.cyclomatic_complexity}, Args: {fn.arg_count}, "
                        f"Docstring: {'Yes' if fn.has_docstring else 'No'}, "
                        f"Types: {'Yes' if fn.has_type_annotations else 'No'}"
                    )

            if file_rep.issues:
                for issue in file_rep.issues:
                    print(
                        f"    [{issue.severity}] L{issue.line}:{issue.column} "
                        f"[{issue.rule_id}] {issue.message}"
                    )
                    if issue.suggestion:
                        print(f"        Suggested Fix: {issue.suggestion}")
                print()

        print(divider)
        print("RECOMMENDATIONS & ARCHITECTURAL CONCLUSION:")
        print(sub_divider)
        ReviewReporter._print_recommendations(report)
        print(divider + "\n")

    @staticmethod
    def _print_recommendations(report: CodebaseReport) -> None:
        """Generate qualitative architectural advice based on findings."""
        if report.scanned_files_count == 0:
            print("No Python files found for review.")
            return

        crit_count = report.total_issues_by_severity.get("CRITICAL", 0)
        err_count = report.total_issues_by_severity.get("ERROR", 0)
        warn_count = report.total_issues_by_severity.get("WARNING", 0)

        if crit_count > 0:
            print("1. [CRITICAL] Address immediate syntax errors and security vulnerabilities.")
        else:
            print("1. [SECURITY & SYNTAX] Core execution safety checks passed. No critical vulnerabilities found.")

        if err_count > 0:
            print(f"2. [BUGS] Fix {err_count} detected runtime anti-patterns (e.g. mutable default arguments).")
        else:
            print("2. [ROBUSTNESS] Zero anti-patterns with runtime hazards detected.")

        if report.average_maintainability >= 80:
            print("3. [MAINTAINABILITY] High overall index (>=80). Code is clean and modular.")
        elif report.average_maintainability >= 65:
            print("3. [MAINTAINABILITY] Moderate index (65-79). Refactor complex functions into dedicated services.")
        else:
            print("3. [MAINTAINABILITY] Low index (<65). High technical debt, consider modular decomposition.")

        if warn_count > 0:
            print(f"4. [RELIABILITY] Review {warn_count} warnings (bare except clauses, excessive complexity).")


def main() -> int:
    """CLI Entry point for performing codebase review."""
    target_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    reviewer = CodeReviewer(root_path=target_dir)
    report = reviewer.review_codebase()

    if "--json" in sys.argv:
        print(json.dumps(asdict(report), indent=2))
    else:
        ReviewReporter.render_cli(report)

    # Return non-zero status code if critical issues are found
    if report.total_issues_by_severity.get("CRITICAL", 0) > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
