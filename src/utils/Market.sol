// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

enum MarketState {
    PRETRADE,   // Trading not yet active.
    OPEN,       // Trading active.
    CLOSED,     // Trading ended, awaiting resolution.
    RESOLVED,   // Outcome determined.
    INVALID     // Market invalidated.
}

enum MarketType {
    BINARY,         // YES/NO.
    CATEGORICAL,    // Multiple outcomes.
    SCALAR,         // Range-based.
    CONDITIONAL     // Depends on another market.
}

struct MarketInfo {
    MarketState marketState;
    MarketType marketType;
    address creator;
    address resolver;
    string question;
    string description;
    uint16 category;
    uint16 subcategory;
    uint64 createdAt;
    uint64 startTime;
    uint64 endTime;
    uint64 resolvedAt;
}

event Trade(
    address indexed trader,
    bool indexed isYes,
    bool indexed isBuy,
    uint256 shares,
    uint256 cost,
    uint256 newPrice
);