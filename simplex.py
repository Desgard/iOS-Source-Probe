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


if __name__ == '__main__':
    t = Simplex([1, 2])
    t.add_constraint([1, 1], 2)
    t.add_constraint([1, 1], 1)
    print(t.solve)
    print(t.mat)

'''
(-32.0, {2: 1.0, 3: 3.0})
[[32.   1.   0.   0.   2.   0.   0.   4. ]
 [ 1.  -0.5  1.   0.  -0.5  0.   0.   0.5]
 [ 3.   1.5  0.   1.   1.5  0.   0.  -0.5]
 [ 0.  -1.5  0.   0.  -1.5  0.   1.   0.5]
 [ 2.   1.   0.   0.   0.   1.   0.   0. ]]
'''
