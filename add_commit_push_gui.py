import re
import sys
from pathlib import Path

from PySide6.QtCore import QProcess, QTimer
from PySide6.QtGui import QCloseEvent, QIcon, QTextCursor
from PySide6.QtWidgets import (
    QApplication,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QVBoxLayout,
    QWidget,
)


class AddCommitWindow(QMainWindow):
    _CONFIRM_PROMPTS = (
        "Commit and push these changes? [Y/n]:",
        "Do you want to commit and push these changes? [y/N]:",
    )
    _MESSAGE_PATTERN = re.compile(r"Enter commit message(?: \[(.*?)\])?:")

    def __init__(self, core_script: Path) -> None:
        super().__init__()
        self._core_script = core_script
        self._prompt_buffer = ""
        self._awaiting = ""
        self._saw_failure = False

        self._process = QProcess(self)
        self._process.setProgram("/bin/bash")
        self._process.setArguments([str(core_script)])
        self._process.setWorkingDirectory(str(core_script.parent))
        self._process.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self._process.readyReadStandardOutput.connect(self._read_output)
        self._process.finished.connect(self._process_finished)
        self._process.errorOccurred.connect(self._process_error)

        title_suffix = "AI" if "_ai_" in core_script.name else "Classic"
        self.setWindowTitle(f"Add Commit & Push — {title_suffix}")
        self.resize(880, 640)

        icon = self._application_icon()
        if not icon.isNull():
            self.setWindowIcon(icon)

        central_widget = QWidget(self)
        layout = QVBoxLayout(central_widget)

        self._status_label = QLabel("Starting…", central_widget)
        self._output = QPlainTextEdit(central_widget)
        self._output.setReadOnly(True)

        self._prompt_label = QLabel("", central_widget)
        self._prompt_label.setWordWrap(True)

        self._message_edit = QLineEdit(central_widget)
        self._message_edit.setPlaceholderText("Commit message")
        self._message_edit.returnPressed.connect(self._submit_message)

        button_row = QHBoxLayout()
        self._yes_button = QPushButton("Yes", central_widget)
        self._no_button = QPushButton("No", central_widget)
        self._submit_button = QPushButton("Commit", central_widget)
        self._stop_button = QPushButton("Stop", central_widget)
        self._yes_button.clicked.connect(lambda: self._submit_confirmation(True))
        self._no_button.clicked.connect(lambda: self._submit_confirmation(False))
        self._submit_button.clicked.connect(self._submit_message)
        self._stop_button.clicked.connect(self._stop_process)

        button_row.addWidget(self._yes_button)
        button_row.addWidget(self._no_button)
        button_row.addWidget(self._message_edit, 1)
        button_row.addWidget(self._submit_button)
        button_row.addWidget(self._stop_button)

        layout.addWidget(self._status_label)
        layout.addWidget(self._output, 1)
        layout.addWidget(self._prompt_label)
        layout.addLayout(button_row)
        self.setCentralWidget(central_widget)

        self._set_prompt_mode("")
        self._process.start()

    def _application_icon(self) -> QIcon:
        icon_path = Path(__file__).resolve().parent / "assets" / "app_icon.svg"
        if icon_path.is_file():
            return QIcon(str(icon_path))
        return QIcon()

    def _read_output(self) -> None:
        data = bytes(self._process.readAllStandardOutput())
        if not data:
            return

        text = data.decode("utf-8", errors="replace")
        sys.stdout.write(text)
        sys.stdout.flush()

        self._output.moveCursor(QTextCursor.MoveOperation.End)
        self._output.insertPlainText(text)
        self._output.moveCursor(QTextCursor.MoveOperation.End)

        failure_text = text.casefold()
        if (
            "commit failed" in failure_text
            or "push failed" in failure_text
            or "fatal:" in failure_text
            or "error:" in failure_text
        ):
            self._saw_failure = True

        self._prompt_buffer = (self._prompt_buffer + text)[-4096:]
        if not self._awaiting:
            self._detect_prompt()

    def _detect_prompt(self) -> None:
        for prompt in self._CONFIRM_PROMPTS:
            if prompt in self._prompt_buffer:
                self._awaiting = "confirm"
                self._prompt_label.setText("Commit and push these changes?")
                self._status_label.setText("Waiting for Yes / No")
                self._set_prompt_mode("confirm")
                return

        matches = list(self._MESSAGE_PATTERN.finditer(self._prompt_buffer))
        if not matches:
            return

        match = matches[-1]
        suggested_message = (match.group(1) or "").strip()
        self._awaiting = "message"
        self._message_edit.setText(suggested_message)
        self._message_edit.selectAll()
        self._message_edit.setFocus()
        self._prompt_label.setText(
            "Enter the commit message."
            + (f" Suggested: {suggested_message}" if suggested_message else "")
        )
        self._status_label.setText("Waiting for commit message")
        self._set_prompt_mode("message")

    def _set_prompt_mode(self, mode: str) -> None:
        confirmation = mode == "confirm"
        message = mode == "message"
        self._yes_button.setVisible(confirmation)
        self._no_button.setVisible(confirmation)
        self._message_edit.setVisible(message)
        self._submit_button.setVisible(message)

    def _submit_confirmation(self, confirmed: bool) -> None:
        if self._awaiting != "confirm":
            return
        self._process.write(b"y\n" if confirmed else b"n\n")
        self._process.waitForBytesWritten(1000)
        self._prompt_buffer = ""
        self._awaiting = ""
        self._prompt_label.setText("")
        self._status_label.setText("Working…")
        self._set_prompt_mode("")

    def _submit_message(self) -> None:
        if self._awaiting != "message":
            return

        message = self._message_edit.text().strip()
        if not message:
            QMessageBox.warning(
                self,
                "Commit message",
                "Enter a commit message.",
            )
            return

        self._process.write((message + "\n").encode("utf-8"))
        self._process.waitForBytesWritten(1000)
        self._prompt_buffer = ""
        self._awaiting = ""
        self._prompt_label.setText("")
        self._message_edit.clear()
        self._status_label.setText("Committing and pushing…")
        self._set_prompt_mode("")

    def _process_finished(
        self,
        exit_code: int,
        _exit_status: QProcess.ExitStatus,
    ) -> None:
        final_exit_code = exit_code
        if final_exit_code == 0 and self._saw_failure:
            final_exit_code = 1

        if final_exit_code == 0:
            self._status_label.setText("Finished")
        else:
            self._status_label.setText(f"Failed — exit code {final_exit_code}")

        self._set_prompt_mode("")
        self._stop_button.setEnabled(False)
        QTimer.singleShot(1200, lambda: QApplication.exit(final_exit_code))

    def _process_error(self, _error: QProcess.ProcessError) -> None:
        message = self._process.errorString()
        sys.stderr.write(message + "\n")
        sys.stderr.flush()
        self._status_label.setText(f"Failed: {message}")
        self._saw_failure = True

    def _stop_process(self) -> None:
        if self._process.state() == QProcess.ProcessState.NotRunning:
            return
        self._process.terminate()
        if not self._process.waitForFinished(1500):
            self._process.kill()

    def closeEvent(self, event: QCloseEvent) -> None:
        if self._process.state() != QProcess.ProcessState.NotRunning:
            answer = QMessageBox.question(
                self,
                "Stop Add Commit?",
                "The commit helper is still running. Stop it and close?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if answer != QMessageBox.StandardButton.Yes:
                event.ignore()
                return
            self._stop_process()
        event.accept()


class AddCommitApplication:
    @staticmethod
    def run() -> int:
        if len(sys.argv) < 2:
            raise SystemExit("Usage: add_commit_push_gui.py <core-script>")

        core_script = Path(sys.argv[1]).expanduser().resolve()
        if not core_script.is_file():
            raise FileNotFoundError(f"Core script not found: {core_script}")

        application = QApplication.instance() or QApplication(sys.argv)
        application.setApplicationName("ND Add Commit")
        icon_path = Path(__file__).resolve().parent / "assets" / "app_icon.svg"
        if icon_path.is_file():
            icon = QIcon(str(icon_path))
            if not icon.isNull():
                application.setWindowIcon(icon)

        window = AddCommitWindow(core_script)
        window.show()
        return application.exec()


if __name__ == "__main__":
    raise SystemExit(AddCommitApplication.run())
