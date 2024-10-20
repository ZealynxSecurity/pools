// SPDX-License-Identifier: UNLICENSED
// solhint-disable
pragma solidity ^0.8.17;

uint256 constant EPOCHS_DURATION_SECONDS = 30;
uint256 constant SECONDS_IN_HOUR = 60 * 60;
uint256 constant SECONDS_IN_DAY = 24 * SECONDS_IN_HOUR;
uint256 constant EPOCHS_IN_HOUR = SECONDS_IN_HOUR / EPOCHS_DURATION_SECONDS;
uint256 constant EPOCHS_IN_DAY = 24 * EPOCHS_IN_HOUR;
uint256 constant EPOCHS_IN_WEEK = 7 * EPOCHS_IN_DAY;
uint256 constant EPOCHS_IN_YEAR = 365 * EPOCHS_IN_DAY;
uint256 constant EPOCHS_IN_18_MONTHS = 547 * EPOCHS_IN_DAY;
