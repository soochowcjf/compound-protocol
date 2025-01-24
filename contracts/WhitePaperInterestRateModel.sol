pragma solidity ^0.5.16;

import "./InterestRateModel.sol";
import "./SafeMath.sol";

// 直线型
/**
  * @title Compound's WhitePaperInterestRateModel Contract
  * @author Compound
  * @notice The parameterized model described in section 2.4 of the original Compound Protocol whitepaper
  */
contract WhitePaperInterestRateModel is InterestRateModel {
    using SafeMath for uint;

    event NewInterestParams(uint baseRatePerBlock, uint multiplierPerBlock);

    uint256 private constant BASE = 1e18;

    // 表示一年内的区块数，是按照每15s出一个区块计算得出
    /**
     * @notice The approximate number of blocks per year that is assumed by the interest rate model
     */
    uint public constant blocksPerYear = 2102400;

    // k
    /**
     * @notice The multiplier of utilization rate that gives the slope of the interest rate
     */
    uint public multiplierPerBlock;

    // b
    /**
     * @notice The base interest rate which is the y-intercept when utilization rate is 0
     */
    uint public baseRatePerBlock;

    //    y = k*x + b
    //    x：资金使用率
    /**
     * @notice Construct an interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     */
    constructor(uint baseRatePerYear, uint multiplierPerYear) public {
        // 基准年利率，其实就是公式中的b值
        baseRatePerBlock = baseRatePerYear.div(blocksPerYear);
        // 其实就是斜率 k 值
        multiplierPerBlock = multiplierPerYear.div(blocksPerYear);

        emit NewInterestParams(baseRatePerBlock, multiplierPerBlock);
    }

    // 资金使用率 = 总借款 / (资金池余额 + 总借款 - 储备金)
    // utilizationRate = borrows / (cash + borrows - reserves)
    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market (currently unused)
     * @return The utilization rate as a mantissa between [0, 1e18]
     */
    function utilizationRate(uint cash, uint borrows, uint reserves) public pure returns (uint) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return borrows.mul(1e18).div(cash.add(borrows).sub(reserves));
    }

    // 借款利率
    /**
     * @notice Calculates the current borrow rate per block, with the error code expected by the market
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow rate percentage per block as a mantissa (scaled by 1e18)
     */
    function getBorrowRate(uint cash, uint borrows, uint reserves) public view returns (uint) {
        // 计算出资金使用率，相当于x
        uint ur = utilizationRate(cash, borrows, reserves);
        // 计算y=kx+b
        // div(1e18) 则是因为 ur 和 multiplierPerBlock 本身都已经扩为高精度整数了，相乘之后精度变成 36 了，所以再除以 1e18 就可以把精度降回 18。
        return ur.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock);
    }

    // 存款利率 = 资金使用率 * 借款利率 *（1 - 储备金率）
    // supplyRate = utilizationRate * borrowRate * (1 - reserveFactor)
    /**
     * @notice Calculates the current supply rate per block
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The supply rate percentage per block as a mantissa (scaled by 1e18)
     */
    function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa) public view returns (uint) {
        uint oneMinusReserveFactor = uint(1e18).sub(reserveFactorMantissa);
        uint borrowRate = getBorrowRate(cash, borrows, reserves);
        uint rateToPool = borrowRate.mul(oneMinusReserveFactor).div(1e18);
        return utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18);
    }
}
