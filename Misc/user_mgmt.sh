#!/bin/bash

# Validate username: non-empty, no whitespace-only
validate_username() {
    local username="$1"
    if [[ -z "$username" || "$username" =~ ^[[:space:]]+$ ]]; then
        echo "Error: Username cannot be empty or whitespace-only." >&2
        return 1
    fi
    return 0
}

# Function to create a user
create_user() {
    read -p "Enter Username: " username

    if ! validate_username "$username"; then
        return 1
    fi

    if id "$username" &>/dev/null; then
        echo "Error: User '$username' already exists." >&2
        return 1
    fi

    if sudo useradd -m "$username"; then
        echo "User '$username' created successfully."
    else
        echo "Error: Failed to create user '$username'." >&2
        return 1
    fi
}

# Function to delete a user
del_user() {
    read -p "Enter Username: " username

    if ! validate_username "$username"; then
        return 1
    fi

    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist." >&2
        return 1
    fi

    if sudo deluser --remove-home "$username"; then
        echo "User '$username' deleted successfully."
    else
        echo "Error: Failed to delete user '$username'." >&2
        return 1
    fi
}

# Main control flow - dispatch based on argument
case "$1" in
    c)
        create_user
        exit $?
        ;;
    d)
        del_user
        exit $?
        ;;
    *)
        echo "Usage: $0 {c|d}" >&2
        echo "  c  - Create a new user" >&2
        echo "  d  - Delete an existing user" >&2
        exit 1
        ;;
esac
