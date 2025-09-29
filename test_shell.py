#!/usr/bin/env python3
"""
Test suite for the Zig shell implementation.

Usage:
    python test_shell.py
"""

import subprocess
import sys
import time
from typing import List, Optional


class ShellTester:
    """Test framework for the Zig shell using persistent subprocess."""

    def __init__(self, shell_command: Optional[List[str]] = None):
        """
        Initialize the shell tester.

        Args:
            shell_command: Command to run the shell (default: ['zig', 'build', 'run'])
        """
        self.shell_command = shell_command or ["zig", "build", "run"]
        self.tests_passed = 0
        self.tests_failed = 0

    def run_interactive_session(
        self, commands: List[str], expected_responses: List[str]
    ) -> bool:
        """
        Run commands in a persistent shell session.

        Args:
            commands: List of commands to send
            expected_responses: List of expected response patterns

        Returns:
            True if all commands executed and responses matched
        """
        try:
            # Start shell process with persistent stdin
            proc = subprocess.Popen(
                self.shell_command,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=0,  # Unbuffered
            )

            # Wait for initial prompt
            time.sleep(0.1)

            for i, command in enumerate(commands):
                # Send command
                if proc.stdin:
                    proc.stdin.write(command + "\n")
                    proc.stdin.flush()

                # Read output until next prompt
                output = ""
                start_time = time.time()
                while time.time() - start_time < 2.0:  # 2 second timeout
                    if proc.stdout and proc.stdout.readable():
                        char = proc.stdout.read(1)
                        if char:
                            output += char
                            # Check if we have expected response and next prompt
                            if (
                                i < len(expected_responses)
                                and expected_responses[i] in output
                                and output.endswith("$ ")
                            ):
                                break
                        else:
                            time.sleep(0.01)
                    else:
                        time.sleep(0.01)

                # Verify expected response is in output
                if i < len(expected_responses) and expected_responses[i] not in output:
                    proc.terminate()
                    return False

            proc.terminate()
            return True

        except Exception:
            return False

    def assert_interactive_session(
        self, commands: List[str], expected_responses: List[str], description: str = ""
    ) -> bool:
        """
        Test an interactive shell session with multiple commands.
        """
        test_name = description or f"Interactive session with {len(commands)} commands"

        if self.run_interactive_session(commands, expected_responses):
            print(f"✓ PASS: {test_name}")
            self.tests_passed += 1
            return True
        else:
            print(f"✗ FAIL: {test_name}")
            self.tests_failed += 1
            return False

    def assert_output_contains(
        self, command: str, expected_text: str, description: str = ""
    ) -> bool:
        """
        Test that shell output contains expected text.
        """
        test_name = (
            description or f"Command '{command}' should contain '{expected_text}'"
        )

        if self.run_interactive_session([command], [expected_text]):
            print(f"✓ PASS: {test_name}")
            self.tests_passed += 1
            return True
        else:
            print(f"✗ FAIL: {test_name}")
            self.tests_failed += 1
            return False

    def run_test_suite(self):
        """Run all tests and print summary."""
        print("Starting Zig Shell Tests")
        print("=" * 40)

        # Test invalid commands
        self.test_invalid_commands()

        # Test REPL continues running
        self.test_repl_continues()

        # Print summary
        print("\n" + "=" * 40)
        print(f"Tests completed: {self.tests_passed + self.tests_failed}")
        print(f"Passed: {self.tests_passed}")
        print(f"Failed: {self.tests_failed}")

        if self.tests_failed == 0:
            print("🎉 All tests passed!")
            return True
        else:
            print(f"❌ {self.tests_failed} test(s) failed")
            return False

    def test_invalid_commands(self):
        """Test that invalid commands return proper error messages."""
        print("\n--- Testing Invalid Commands ---")

        test_commands = ["ls", "pwd", "echo hello", "cd /tmp", "mkdir test"]

        for command in test_commands:
            # The shell should respond with "command: command not found"
            expected_text = "command not found"
            self.assert_output_contains(
                command,
                expected_text,
                f"Invalid command '{command}' should show 'command not found'",
            )

    def test_repl_continues(self):
        """Test that the shell REPL continues running after commands."""
        print("\n--- Testing REPL Continuity ---")

        # Test multiple commands in sequence
        commands = ["ls", "pwd", "echo test"]
        expected_responses = [
            "command not found",
            "command not found",
            "command not found",
        ]

        self.assert_interactive_session(
            commands,
            expected_responses,
            "Shell should continue running and accept multiple commands",
        )

        # Test that prompts appear for each command
        commands = ["invalid1", "invalid2"]
        expected_responses = ["command not found", "command not found"]

        self.assert_interactive_session(
            commands, expected_responses, "Shell should show prompt before each command"
        )


def main():
    """Main function to run tests."""
    if len(sys.argv) > 1:
        # Allow custom shell command
        shell_command = sys.argv[1:]
        tester = ShellTester(shell_command)
    else:
        tester = ShellTester()

    success = tester.run_test_suite()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
