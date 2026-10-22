"""User-facing guidance for device operations with ambiguous outcomes."""


def sideload_result_message(returncode: int, output: str) -> tuple[str, str]:
    """Describe sideload completion without overstating what the exit code proves."""
    details = output.strip() or "No command output was captured."
    if returncode == 0:
        return (
            "Sideload complete",
            "ADB reported that the sideload command completed. This alone does not "
            "verify that Android accepted or booted the update.\n\n" + details,
        )
    return (
        "Sideload outcome uncertain",
        f"ADB did not report successful completion (exit status {returncode}). The update may "
        "have been rejected, interrupted, or left in an uncertain state; this result "
        "does not prove that no changes were made. Do not immediately retry the ZIP. "
        "Check the device's recovery screen and command output, confirm the device "
        "state, and follow the package/device vendor's recovery guidance before "
        f"retrying.\n\nOutput:\n{details}",
    )
