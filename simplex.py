import numpy as np


class Simplex_old(object):

    def __init__(self, obj, max_mode=False):
        # 默认是解决 min LP 问题，如果是最大值用 True，要 mut -1
        self.max_mode = max_mode
        self.mat = np.array([[0] + obj]) * (-1 if max_mode else 1)

    def add_constraint(self, a, b):
        # 增加约束，即在矩阵最后一行增加
        self.mat = np.vstack([self.mat, [b] + a])

    @property
    def solve(self):
        # 获得矩阵的纬度
        m, n = self.mat.shape
        # 零矩阵和对角矩阵上下排列
        temp, B = np.vstack([np.zeros((1, m - 1)), np.eye(m - 1)]), list(range(n - 1, n + m - 1))
        # 组合系数矩阵
        mat = self.mat = np.hstack([self.mat, temp])
        # 循环所有目标函数的系数,直到全部没有负数为止
        while mat[0, 1:].min() < 0:
            # 1. 选择合适的替入和替出变量
            # Bland 规则对矩阵做退化操
            col = np.where(mat[0, 1:] < 0)[0][0] + 1
            row = np.array([mat[i][0] / mat[i][col] if mat[i][col] > 0 else 0x7fffffff for i in
                            range(1, mat.shape[0])]).argmin() + 1  # find the theta index
            # 如果没有替出变量,则说明原问题无界
            if mat[row][col] <= 0: return None

            # 2. 旋转过程
            # 系数归一,整行相除
            mat[row] /= mat[row][col]
            # 对所有 i!= row 进行 mat[i]= mat[i] - mat[row] * mat[i][col] 操作
            ids = np.arange(mat.shape[0]) != row
            mat[ids] -= mat[row] * mat[ids, col:col + 1]
            B[row] = col
        # 返回目标值,若为最小值,则要 * -1,最大值则不用。
        # 后面的矩阵是各个解的系数矩阵,基本变量对应 bi,非基本变量为0
        # B[i] < n 判断即为删除松弛增加的变量
        return mat[0][0] * (1 if self.max_mode else -1), {B[i]: mat[i, 0] for i in range(1, m) if B[i] < n}


class Simplex(object):

    def __init__(self, obj, max_mode=False):
        # 默认是解决 min LP 问题，如果是最大值用 True，要 mut -1
        self.mat, self.max_mode = np.array([[0] + obj]) * (-1 if max_mode else 1), max_mode

    # 增加约束
    def add_constraint(self, a, b):
        # 增加约束，即在矩阵最后一行增加
        self.mat = np.vstack([self.mat, [b] + a])

    # Simplex 算法过程
    def _simplex(self, mat, B, m, n):
        while mat[0, 1:].min() < 0:
            # Bland 规则对矩阵做退化操
            col = np.where(mat[0, 1:] < 0)[0][0] + 1
            row = np.array([mat[i][0] / mat[i][col] if mat[i][col] > 0 else 0x7fffffff for i in
                            range(1, mat.shape[0])]).argmin() + 1
            # 如果没有替出变量,则说明原问题无界
            if mat[row][col] <= 0: return None  # the theta is ∞, the problem is unbounded
            self._pivot(mat, B, row, col)
        # 返回目标值,若为最小值,则要 * -1,最大值则不用。
        # 后面的矩阵是各个解的系数矩阵,基本变量对应 bi,非基本变量为0
        # B[i] < n 判断即为删除松弛增加的变量
        return mat[0][0] * (1 if self.max_mode else -1), {B[i]: mat[i, 0] for i in range(1, m) if B[i] < n}

    # 旋转过程
    def _pivot(self, mat, B, row, col):
        # 对所有 i!= row 进行 mat[i]= mat[i] - mat[row] * mat[i][col] 操作
        mat[row] /= mat[row][col]
        ids = np.arange(mat.shape[0]) != row
        mat[ids] -= mat[row] * mat[ids, col:col + 1]
        B[row] = col

    def solve(self):
        # 获得矩阵的纬度
        m, n = self.mat.shape
        # 组合系数矩阵
        temp, B = np.vstack([np.zeros((1, m - 1)), np.eye(m - 1)]), list(range(n - 1, n + m - 1))
        # 循环所有目标函数的系数,直到全部没有负数为止
        mat = self.mat = np.hstack([self.mat, temp])  # combine them!
        # 判断最小的常数 b 是否存在小于 0 的情况,有的话则初始解不可行
        if mat[1:, 0].min() < 0:
            # 找到最小 b 的那一列
            row = mat[1:, 0].argmin() + 1
            # temp 保存原先的目标函数, 第0行设置为0
            temp, mat[0] = np.copy(mat[0]), 0
            # 添加 x0 需要拼接的矩阵,构造辅助线性规划
            mat = np.hstack([mat, np.array([1] + [-1] * (m - 1)).reshape((-1, 1))])
            # 执行一次旋转操作,将系数b最小的那一项替出
            self._pivot(mat, B, row, mat.shape[1] - 1)
            # 求解辅助线性规划,如果最优值为0,则有解,否则无解
            if self._simplex(mat, B, m, n)[0] != 0: return None

            # 若x0是基本解,需要将 x0 替出
            if mat.shape[1] - 1 in B:
                # 增加一次旋转来替出 x0
                self._pivot(mat, B, B.index(mat.shape[1] - 1), np.where(mat[0, 1:] != 0)[0][0] + 1)

            # 恢复目标函数
            self.mat = np.vstack([temp, mat[1:, :-1]])  # recover the first line
            for i, x in enumerate(B[1:]):
                self.mat[0] -= self.mat[0, x] * self.mat[i + 1]
        return self._simplex(self.mat, B, m, n)

if __name__ == '__main__':
    t = Simplex([0, 1], max_mode=True)
    t.add_constraint([1, 1], 250)
    t.add_constraint([-1, 0], -50)
    print(t.solve())
    print(t.mat)

