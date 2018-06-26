import numpy as np


class Simplex(object):

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
        while mat[0, 1:].min() < 0:
            # Bland 规则对矩阵做退化操作
            col = np.where(mat[0, 1:] < 0)[0][0] + 1
            row = np.array([mat[i][0] / mat[i][col] if mat[i][col] > 0 else 0x7fffffff for i in
                            range(1, mat.shape[0])]).argmin() + 1  # find the theta index
            if mat[row][col] <= 0: return None  # the theta is ∞, the problem is unbounded
            mat[row] /= mat[row][col]
            ids = np.arange(mat.shape[0]) != row
            mat[ids] -= mat[row] * mat[ids, col:col + 1]  # for each i!= row do: mat[i]= mat[i] - mat[row] * mat[i][col]
            B[row] = col
        return mat[0][0] * (1 if self.max_mode else -1), {B[i]: mat[i, 0] for i in range(1, m) if B[i] < n}


if __name__ == '__main__':
    t = Simplex([-1, -14, -6])
    t.add_constraint([1, 1, 1], 4)
    t.add_constraint([1, 0, 0], 2)
    t.add_constraint([0, 0, 1], 3)
    t.add_constraint([0, 3, 1], 6)
    print(t.solve)
    print(t.mat)
