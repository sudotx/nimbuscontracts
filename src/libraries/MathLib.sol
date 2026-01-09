// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MathLib
 * @notice Mathematical operations for prediction markets
 */
library MathLib {
    /**
     * @notice Calculate square root using Babylonian method
     * @param x Value to calculate square root of
     * @return y Square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;

        uint256 z = (x + 1) / 2;
        y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /**
     * @notice Multiply two numbers and divide by a denominator with rounding up
     * @param x First multiplicand
     * @param y Second multiplicand
     * @param denominator Divisor
     * @return result Result of (x * y) / denominator rounded up
     */
    function mulDivUp(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        uint256 prod = x * y;
        result = prod / denominator;
        if (prod % denominator != 0) {
            result += 1;
        }
    }

    /**
     * @notice Multiply two numbers and divide by a denominator with rounding down
     * @param x First multiplicand
     * @param y Second multiplicand
     * @param denominator Divisor
     * @return result Result of (x * y) / denominator rounded down
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        return (x * y) / denominator;
    }

    /**
     * @notice Calculate percentage with basis points precision
     * @param amount Amount to calculate percentage of
     * @param _bps Basis points to apply
     * @return result The calculated amount in basis points
     */
    function bps(uint256 amount, uint256 _bps) internal pure returns (uint256) {
        return (amount * _bps) / 10000;
    }

    /**
     * @notice Minimum of two numbers
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Maximum of two numbers
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
